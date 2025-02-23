package raytracer

import "core:fmt"
import "core:log"
import "core:os"
import vkb "external:odin-vk-bootstrap"
import vma "external:odin-vma"
import vk "vendor:vulkan"
_ :: fmt

Backend_Error :: union #shared_nil {
	vk.Result,
	Initialization_Error,
	Shader_Error,
	// Image_Aquiring_Error,
}

Initialization_Error :: enum {
	Success = 0,
	CreatingInstance,
	ChoosingDevice,
	CreatingDevice,
	CreatingSwapchain,
	GettingQueue,
}

Context :: struct {
	device:                ^vkb.Device,
	instance:              ^vkb.Instance,
	surface:               vk.SurfaceKHR,
	swapchain:             Swapchain,
	descriptor_set_layout: Descriptor_Set_Layout,
	pipeline:              Pipeline,
	graphics_queue:        vk.Queue,
	present_queue:         vk.Queue,
	physical_device:       ^vkb.Physical_Device,
	frame_manager:         Frame_Manager,
	allocator:             vma.Allocator,
	transfer_command_pool: Command_Pool,
	descriptor_pool:       Descriptor_Pool,
}

Swapchain :: struct {
	using _internal: ^vkb.Swapchain,
	images:          []vk.Image,
	image_views:     []vk.ImageView,
}

context_init :: proc(
	ctx: ^Context,
	window: ^Window,
	allocator := context.allocator,
) -> (
	err: Backend_Error,
) {
	{ 	// Create instance
		builder, instance_ok := vkb.init_instance_builder()
		if !instance_ok {
			return .CreatingInstance
		}
		defer vkb.destroy_instance_builder(&builder)


		vkb.instance_set_minimum_version(&builder, vk.API_VERSION_1_3)

		when ODIN_DEBUG {
			vkb.instance_request_validation_layers(&builder)
			vkb.instance_use_default_debug_messenger(&builder)
		}

		ok: bool
		if ctx.instance, ok = vkb.build_instance(&builder); !ok {
			return .CreatingInstance
		}
	}

	ctx.surface = window_get_surface(window, ctx.instance) or_return

	{ 	// choose physical device
		selector, selector_ok := vkb.init_physical_device_selector(ctx.instance)
		if !selector_ok {
			return .ChoosingDevice
		}
		defer vkb.destroy_physical_device_selector(&selector)

		vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
		vkb.selector_set_required_features_13(&selector, {dynamicRendering = true})
		vkb.selector_set_surface(&selector, ctx.surface)

		ok: bool
		if ctx.physical_device, ok = vkb.select_physical_device(&selector, allocator = allocator);
		   !ok {
			return .ChoosingDevice
		}
	}

	{ 	// logical device
		builder, device_ok := vkb.init_device_builder(ctx.physical_device)
		if !device_ok {
			return .CreatingDevice
		}
		defer vkb.destroy_device_builder(&builder)

		ok: bool
		if ctx.device, ok = vkb.build_device(&builder, allocator); !ok {
			return .CreatingDevice
		}
	}

	ctx.swapchain = make_swapchain(ctx, window^) or_return

	{ 	// get queues
		ok: bool
		if ctx.graphics_queue, ok = vkb.device_get_queue(ctx.device, .Graphics); !ok {
			return .GettingQueue

		}
		if ctx.present_queue, ok = vkb.device_get_queue(ctx.device, .Present); !ok {
			return .GettingQueue
		}
	}


	shaders: []Shader_Module
	shaders = make([]Shader_Module, 2, allocator)

	shaders[0] = make_vertex_shader_module(ctx.device, "shaders/vert.spv", "main") or_return
	shaders[1] = make_fragment_shader_module(ctx.device, "shaders/frag.spv", "main") or_return

	{ 	// create descriptor set layout
		builder := create_descriptor_set_layout_builder(ctx.device.ptr, allocator)

		descriptor_set_layout_add_binding(&builder, 0, .UNIFORM_BUFFER, {.VERTEX})

		ctx.descriptor_set_layout = create_descriptor_set_layout(builder) or_return
	}

	ctx.pipeline = create_graphics_pipeline(ctx^, shaders) or_return

	{
		vma_functions := vma.create_vulkan_functions()
		// create allocator
		create_info := vma.Allocator_Create_Info {
			vulkan_api_version = vkb.convert_vulkan_to_vma_version(ctx.instance.api_version),
			physical_device    = ctx.physical_device.ptr,
			device             = ctx.device.ptr,
			instance           = ctx.instance.ptr,
			vulkan_functions   = &vma_functions,
		}

		vk_must(
			vma.create_allocator(create_info, &ctx.allocator),
			"Failed to create VMA allocator",
		)
	}

	ctx.transfer_command_pool = make_command_pool(
		ctx.device,
		"Transfer Command Pool",
		{.TRANSIENT},
	) or_return

	{ 	// create descriptor pool
		builder := create_descriptor_pool_builder(
			ctx.device.ptr,
			MAX_FRAMES_IN_FLIGHT,
			allocator = allocator,
		)
		descriptor_pool_add_pool_size(&builder, .UNIFORM_BUFFER, MAX_FRAMES_IN_FLIGHT)

		ctx.descriptor_pool = create_descriptor_pool(builder) or_return
	}

	// ctx.frame_manager = make_frame_manager(ctx, allocator = allocator) or_return

	return nil
}

@(require_results)
make_swapchain :: proc(
	ctx: ^Context,
	window: Window,
	allocator := context.allocator,
) -> (
	swapchain: Swapchain,
	err: Backend_Error,
) {
	// create swapchain
	builder, swapchain_ok := vkb.init_swapchain_builder(ctx.device)
	if !swapchain_ok {
		return {}, .CreatingSwapchain
	}
	defer vkb.destroy_swapchain_builder(&builder)

	vkb.swapchain_builder_set_old_swapchain(&builder, ctx.swapchain)
	extent := window_get_extent(window)
	vkb.swapchain_builder_set_desired_extent(&builder, extent.width, extent.height)
	vkb.swapchain_builder_use_default_format_selection(&builder)
	vkb.swapchain_builder_set_present_mode(&builder, .FIFO)
	vkb.swapchain_builder_set_present_mode(&builder, .MAILBOX)

	ok: bool
	if swapchain._internal, ok = vkb.build_swapchain(&builder); !ok {
		return {}, .CreatingSwapchain
	}

	if swapchain.images, ok = vkb.swapchain_get_images(swapchain, allocator = allocator); !ok {
		return {}, .CreatingSwapchain
	}
	if swapchain.image_views, ok = vkb.swapchain_get_image_views(swapchain, allocator = allocator);
	   !ok {
		return {}, .CreatingSwapchain
	}

	return swapchain, nil
}

delete_swapchain :: proc(swapchain: Swapchain) {
	vkb.swapchain_destroy_image_views(swapchain, swapchain.image_views)
	delete(swapchain.images)
	delete(swapchain.image_views)
	vkb.destroy_swapchain(swapchain)
}

// TODO: make the recreation of the swapchain using the old_swapchain ptr so I can render and resize at the same time
handle_resize :: proc(
	ctx: ^Context,
	window: Window,
	allocator := context.allocator,
) -> (
	err: Backend_Error,
) {
	window_extent := window_get_extent(window)
	for window_extent.width == 0 && window_extent.height == 0 {
		window_extent = window_get_extent(window)
		window_wait_events(window)
	}

	vk.DeviceWaitIdle(ctx.device.ptr)

	// old_swapchain := ctx.swapchain
	old_swapchain := ctx.swapchain
	defer if old_swapchain._internal != nil {
		delete_swapchain(old_swapchain)

		// frame_manager_handle_resize(ctx)
		// ctx.frame_manager, err = make_frame_manager(ctx, resizing = true)
	}

	ctx.swapchain = make_swapchain(ctx, window, allocator = allocator) or_return

	return nil
}

delete_context :: proc(ctx: ^Context) {
	vk.DeviceWaitIdle(ctx.device.ptr)

	descriptor_pool_destroy(ctx.descriptor_pool)
	// delete_frame_manager(ctx)
	pipeline_destroy(ctx.pipeline, ctx.device)
	descriptor_set_layout_destroy(ctx.descriptor_set_layout)
	delete_command_pool(&ctx.transfer_command_pool)

	delete_swapchain(ctx.swapchain)
	vma.destroy_allocator(ctx.allocator)
	vkb.destroy_device(ctx.device)
	vkb.destroy_surface(ctx.instance, ctx.surface)

	vkb.destroy_instance(ctx.instance)
}

@(private)
vk_must :: proc(result: vk.Result, message: string) {
	if result != .SUCCESS {
		log.fatalf(fmt.tprintf("%s: \x1b[31m%v\x1b[0m", message, result))
		os.exit(1)
	}
}
