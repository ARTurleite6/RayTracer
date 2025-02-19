package raytracer

import "base:runtime"
import "core:log"
import "core:slice"
import "vendor:glfw"
import vk "vendor:vulkan"
_ :: slice

g_context: runtime.Context

Context :: struct {
	device:          Device,
	instance:        Instance,
	surface:         vk.SurfaceKHR,
	swapchain:       Swapchain,
	pipeline:        Pipeline,
	// shaders:         []Shader_Module,
	physical_device: Physical_Device_Info,
	frame_manager:   Frame_Manager,
	debugger:        Debugger,
}

Context_Error :: union #shared_nil {
	Shader_Error,
	vk.Result,
}

@(require_results)
make_context :: proc(
	window: Window,
	allocator := context.allocator,
) -> (
	ctx: Context,
	err: Context_Error,
) {
	g_context = context
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	debug_create_info: ^vk.DebugUtilsMessengerCreateInfoEXT
	when ODIN_DEBUG {
		util_debug_info := debugger_info()
		debug_create_info = &util_debug_info
	}
	ctx.instance = make_instance(
		"Raytracing",
		required_extensions(context.temp_allocator),
		debug_create_info,
	) or_return

	when ODIN_DEBUG {
		ctx.debugger = make_debugger(ctx.instance) or_return
	}

	ctx.surface = window_make_surface(window, ctx.instance) or_return
	ctx.physical_device = choose_physical_device(ctx.instance, ctx.surface) or_return
	ctx.device = make_logical_device(ctx.physical_device) or_return
	ctx.swapchain = make_swapchain(
		ctx.device,
		ctx.physical_device.handle,
		ctx.surface,
		window_get_extent(window),
	) or_return

	shaders: []Shader_Module
	{ 	// create shaders
		shaders = make([]Shader_Module, 2, allocator)

		shaders[0] = make_vertex_shader_module(ctx.device, "shaders/vert.spv", "main") or_return
		shaders[1] = make_fragment_shader_module(ctx.device, "shaders/frag.spv", "main") or_return
	}

	ctx.pipeline = make_graphics_pipeline(ctx.device, ctx.swapchain, shaders) or_return

	ctx.frame_manager = make_frame_manager(ctx, allocator) or_return
	return
}

find_memory_type :: proc(
	ctx: Context,
	type_filter: u32,
	properties: vk.MemoryPropertyFlags,
) -> u32 {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(ctx.physical_device.handle, &mem_properties)

	for i in 0 ..< mem_properties.memoryTypeCount {
		if type_filter & (1 << i) != 0 &&
		   mem_properties.memoryTypes[i].propertyFlags & properties == properties {
			return i
		}
	}

	log.fatalf("No memory type found with type %d and properties %v", type_filter, properties)
	unreachable()
}

// TODO: make the recreation of the swapchain using the old_swapchain ptr so I can render and resize at the same time
handle_resize :: proc(
	ctx: ^Context,
	window: Window,
	allocator := context.allocator,
) -> (
	result: vk.Result,
) {
	window_extent := window_get_extent(window)
	for window_extent.width == 0 && window_extent.height == 0 {
		window_extent = window_get_extent(window)
		window_wait_events(window)
	}

	vk.DeviceWaitIdle(ctx.device.handle)

	// old_swapchain := ctx.swapchain
	old_swapchain := ctx.swapchain
	defer if old_swapchain.handle != 0 {
		delete_swapchain(old_swapchain, ctx.device)

		delete_frame_manager(ctx)
		ctx.frame_manager, result = make_frame_manager(ctx^)
	}

	ctx.swapchain = make_swapchain(
		ctx.device,
		ctx.physical_device.handle,
		ctx.surface,
		window_extent,
		old_swapchain,
		allocator = allocator,
	) or_return

	return
}

delete_context :: proc(ctx: ^Context) {
	vk.DeviceWaitIdle(ctx.device.handle)

	delete_frame_manager(ctx)
	delete_pipeline(ctx.pipeline, ctx.device)
	// for shader in ctx.shaders {
	// 	delete_shader_module(ctx.device, shader)
	// }

	delete_swapchain(ctx.swapchain, ctx.device)
	delete_logical_device(ctx.device)
	vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)

	delete_debugger(ctx.debugger, ctx.instance)
	delete_instance(ctx.instance)
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
