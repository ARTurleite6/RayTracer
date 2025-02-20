package raytracer

import "core:fmt"
import "core:log"
import "core:os"
import "core:slice"
import vkb "external:odin-vk-bootstrap"
import vma "external:odin-vma"
import "vendor:glfw"
import vk "vendor:vulkan"
_ :: fmt
_ :: slice

Context :: struct {
	device:                ^vkb.Device,
	instance:              ^vkb.Instance,
	surface:               vk.SurfaceKHR,
	swapchain:             Swapchain,
	pipeline:              Pipeline,
	graphics_queue:        vk.Queue,
	present_queue:         vk.Queue,
	physical_device:       ^vkb.Physical_Device,
	frame_manager:         Frame_Manager,
	allocator:             vma.Allocator,
	transfer_command_pool: Command_Pool,
}

Swapchain :: struct {
	using _internal: ^vkb.Swapchain,
	images:          []vk.Image,
	image_views:     []vk.ImageView,
}

context_init :: proc(ctx: ^Context, window: Window, allocator := context.allocator) -> (ok: bool) {
	{ 	// Create instance
		builder := vkb.init_instance_builder() or_return
		defer vkb.destroy_instance_builder(&builder)


		vkb.instance_set_minimum_version(&builder, vk.API_VERSION_1_3)

		when ODIN_DEBUG {
			vkb.instance_request_validation_layers(&builder)
			vkb.instance_use_default_debug_messenger(&builder)
		}

		ctx.instance = vkb.build_instance(&builder) or_return
	}

	ctx.surface = window_make_surface(window, ctx.instance) or_return

	{ 	// choose physical device
		selector := vkb.init_physical_device_selector(ctx.instance) or_return
		defer vkb.destroy_physical_device_selector(&selector)

		vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
		vkb.selector_set_required_features_13(&selector, {dynamicRendering = true})
		vkb.selector_set_surface(&selector, ctx.surface)

		ctx.physical_device = vkb.select_physical_device(&selector, allocator = allocator)
	}

	{ 	// logical device
		builder := vkb.init_device_builder(ctx.physical_device) or_return
		defer vkb.destroy_device_builder(&builder)

		ctx.device = vkb.build_device(&builder, allocator) or_return
	}

	ctx.swapchain = make_swapchain(ctx, window) or_return

	{ 	// get queues
		ctx.graphics_queue = vkb.device_get_queue(ctx.device, .Graphics) or_return
		ctx.present_queue = vkb.device_get_queue(ctx.device, .Present) or_return
	}


	shaders: []Shader_Module
	shaders = make([]Shader_Module, 2, allocator)

	shaders[0] = make_vertex_shader_module(ctx.device, "shaders/vert.spv", "main") or_return
	shaders[1] = make_fragment_shader_module(ctx.device, "shaders/frag.spv", "main") or_return

	ctx.pipeline = make_graphics_pipeline(ctx.device, ctx.swapchain, shaders) or_return

	ctx.frame_manager = make_frame_manager(ctx^, allocator) or_return

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

	return true
}

@(require_results)
make_swapchain :: proc(
	ctx: ^Context,
	window: Window,
	allocator := context.allocator,
) -> (
	swapchain: Swapchain,
	ok: bool,
) {
	// create swapchain
	builder := vkb.init_swapchain_builder(ctx.device) or_return
	defer vkb.destroy_swapchain_builder(&builder)

	vkb.swapchain_builder_set_old_swapchain(&builder, ctx.swapchain)
	extent := window_get_extent(window)
	vkb.swapchain_builder_set_desired_extent(&builder, extent.width, extent.height)
	vkb.swapchain_builder_use_default_format_selection(&builder)
	vkb.swapchain_builder_set_present_mode(&builder, .FIFO)
	vkb.swapchain_builder_set_present_mode(&builder, .MAILBOX)

	swapchain._internal = vkb.build_swapchain(&builder) or_return

	swapchain.images = vkb.swapchain_get_images(swapchain, allocator = allocator) or_return
	swapchain.image_views = vkb.swapchain_get_image_views(swapchain, allocator = allocator)

	return swapchain, true
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
	ok: bool,
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

		delete_frame_manager(ctx)
		ctx.frame_manager, ok = make_frame_manager(ctx^)
	}

	ctx.swapchain, ok = make_swapchain(ctx, window, allocator = allocator)

	return
}

delete_context :: proc(ctx: ^Context) {
	vk.DeviceWaitIdle(ctx.device.ptr)

	delete_frame_manager(ctx)
	delete_pipeline(ctx.pipeline, ctx.device)
	// for shader in ctx.shaders {
	// 	delete_shader_module(ctx.device, shader)
	// }

	delete_swapchain(ctx.swapchain)
	vma.destroy_allocator(ctx.allocator)
	vkb.destroy_device(ctx.device)
	vkb.destroy_surface(ctx.instance, ctx.surface)

	vkb.destroy_instance(ctx.instance)
}

@(private = "file")
required_extensions :: proc(allocator := context.allocator) -> []cstring {
	extensions := glfw.GetRequiredInstanceExtensions()

	when ODIN_DEBUG {
		extensions_dyn := slice.to_dynamic(extensions, allocator)
		append(&extensions_dyn, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
		extensions = extensions_dyn[:]
	}

	return extensions
}

@(private)
vk_must :: proc(result: vk.Result, message: string) {
	if result != .SUCCESS {
		log.fatalf(fmt.tprintf("%s: \x1b[31m%v\x1b[0m", message, result))
		os.exit(1)
	}
}

@(private)
@(require_results)
vk_check :: proc(result: vk.Result, message: string) -> bool {
	if result != .SUCCESS {
		log.errorf(fmt.tprintf("%s: \x1b[31m%v\x1b[0m", message, result))
		return false
	}
	return true
}
