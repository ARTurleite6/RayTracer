package raytracer

@(require, extra_linker_flags = "-rpath /usr/local/lib")
foreign import __ "system:System.framework"

import "core:mem"
import "core:slice"
import "vendor:glfw"
import vk "vendor:vulkan"

Context :: struct {
	instance:        Instance,
	physical_device: PhysicalDevice,
	device:          Device,
	present_queue:   vk.Queue,
	graphics_queue:  vk.Queue,
	surface:         vk.SurfaceKHR,
	swapchain:       Swapchain,
	pipeline:        Pipeline,
	debugger:        Debugger,
}

@(require_results)
context_init :: proc(
	ctx: ^Context,
	window: Window,
	allocator: mem.Allocator,
	temp_allocator: mem.Allocator,
) -> (
	result: vk.Result,
) {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
	extensions := required_extensions(temp_allocator)
	debug_info: ^vk.DebugUtilsMessengerCreateInfoEXT
	when ODIN_DEBUG {
		debug_info_value: vk.DebugUtilsMessengerCreateInfoEXT
		debugger_get_info(&debug_info_value)
		debug_info = &debug_info_value
	}

	if result = instance_init(&ctx.instance, "Raytracing", extensions, debug_info);
	   result != .SUCCESS {
		return
	}
	vk.load_proc_addresses(ctx.instance)
	if debug_info != nil {
		debugger_init(&ctx.debugger, ctx.instance, debug_info)
	}

	if ctx.surface, result = window_create_surface(window, ctx.instance); result != .SUCCESS {
		return
	}

	physical_device_init(&ctx.physical_device, ctx.instance, ctx.surface, temp_allocator)

	queues := find_queue_families(ctx.physical_device, ctx.surface, temp_allocator)
	if result = device_init(&ctx.device, ctx.physical_device, ctx.surface, queues, temp_allocator);
	   result != .SUCCESS {
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
		temp_allocator,
	)

	return .SUCCESS
}

context_destroy :: proc(ctx: Context) {
	swapchain_destroy(ctx.swapchain, ctx.device)
	device_destroy(ctx.device)
	vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)
	debugger_destroy(ctx.debugger, ctx.instance)
	instance_destroy(ctx.instance)
}

required_extensions :: proc(temp_allocator: mem.Allocator) -> []cstring {
	extensions := slice.to_dynamic(glfw.GetRequiredInstanceExtensions(), temp_allocator)

	when ODIN_OS == .Darwin {
		append(&extensions, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}

	when ODIN_DEBUG {
		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}

	return extensions[:]
}
