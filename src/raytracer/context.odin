package raytracer

when ODIN_OS == .Darwin {
	@(require, extra_linker_flags = "-rpath /usr/local/lib")
	foreign import __ "system:System.framework"
}

import "core:slice"
import "vendor:glfw"
import vk "vendor:vulkan"

Context_Error :: union #shared_nil {
	vk.Result,
	Shader_Error,
}

Context :: struct {
	instance:        Instance,
	physical_device: PhysicalDevice,
	device:          Device,
	present_queue:   vk.Queue,
	graphics_queue:  vk.Queue,
	surface:         vk.SurfaceKHR,
	swapchain:       Swapchain,
	pipeline:        Pipeline,
	shaders:         []Shader,
	command_pool:    Command_Pool,
	debugger:        Debugger,
}

@(require_results)
context_init :: proc(
	ctx: ^Context,
	window: Window,
	allocator := context.allocator,
) -> (
	result: Context_Error,
) {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
	extensions := required_extensions(context.temp_allocator)
	debug_info: vk.DebugUtilsMessengerCreateInfoEXT
	when ODIN_DEBUG {
		debugger_get_info(&debug_info)
	}

	if result = instance_init(&ctx.instance, "Raytracing", extensions, &debug_info);
	   result != vk.Result.SUCCESS {
		return
	}
	vk.load_proc_addresses(ctx.instance)
	when ODIN_DEBUG {
		debugger_init(&ctx.debugger, ctx.instance, &debug_info)
	}

	if ctx.surface, result = window_create_surface(window, ctx.instance);
	   result != vk.Result.SUCCESS {
		return
	}

	physical_device_init(&ctx.physical_device, ctx.instance, ctx.surface)

	queues := find_queue_families(ctx.physical_device, ctx.surface)
	if result = device_init(&ctx.device, ctx.physical_device, ctx.surface, queues);
	   result != vk.Result.SUCCESS {
		return
	}
	vk.load_proc_addresses_device(ctx.device)

	vk.GetDeviceQueue(ctx.device, queues.graphics.?, 0, &ctx.graphics_queue)
	vk.GetDeviceQueue(ctx.device, queues.present.?, 0, &ctx.present_queue)

	// Go to creating the Swapchain
	swapchain_init(
		&ctx.swapchain,
		ctx.device,
		ctx.physical_device,
		ctx.surface,
		window,
		queues,
		allocator,
	)

	{ 	// create shaders
		// TODO: for now the shaders will be only two and will be hardcoded
		ctx.shaders = make([]Shader, 2, allocator)

		shader_init(&ctx.shaders[0], ctx.device, {.VERTEX}, "main", "shaders/vert.spv") or_return

		shader_init(&ctx.shaders[1], ctx.device, {.FRAGMENT}, "main", "shaders/frag.spv") or_return
	}

	pipeline_init(&ctx.pipeline, ctx.device, &ctx.swapchain, ctx.shaders)

	if result := command_pool_init(&ctx.command_pool, ctx.device, queues.graphics.?);
	   result != .SUCCESS {
		return result
	}

	return
}

context_destroy :: proc(ctx: ^Context) {
	command_pool_destroy(&ctx.command_pool, ctx.device)
	pipeline_destroy(ctx.pipeline, ctx.device)

	for shader in ctx.shaders {
		shader_destroy(shader, ctx.device)
	}
	delete(ctx.shaders)

	swapchain_destroy(ctx.swapchain, ctx.device)
	device_destroy(ctx.device)
	vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)
	debugger_destroy(ctx.debugger, ctx.instance)
	instance_destroy(ctx.instance)
}

required_extensions :: proc(allocator := context.allocator) -> []cstring {
	extensions := slice.to_dynamic(glfw.GetRequiredInstanceExtensions(), allocator)

	when ODIN_OS == .Darwin {
		append(&extensions, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}

	when ODIN_DEBUG {
		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}

	return extensions[:]
}
