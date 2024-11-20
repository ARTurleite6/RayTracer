package raytracer

@(require, extra_linker_flags = "-rpath /usr/local/lib")
foreign import __ "system:System.framework"

import "core:mem"
import "core:slice"
import "vendor:glfw"
import vk "vendor:vulkan"

Context :: struct {
	instance: Instance,
	debugger: Debugger,
}

@(require_results)
context_init :: proc(ctx: ^Context, temp_allocator: mem.Allocator) -> vk.Result {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
	extensions := required_extensions(temp_allocator)
	when ODIN_DEBUG {
		debug_info: vk.DebugUtilsMessengerCreateInfoEXT
		debugger_get_info(&debug_info)
		if result := instance_init(&ctx.instance, "Raytracing", extensions, &debug_info);
		   result != .SUCCESS {
			return result
		}
		vk.load_proc_addresses(ctx.instance)
		debugger_init(&ctx.debugger, ctx.instance, &debug_info)
	} else {
		if result := instance_init(&ctx.instance, "Raytracing", extensions); result != .SUCCESS {
			return result
		}
		vk.load_proc_addresses(ctx.instance)
	}
	return .SUCCESS
}

context_destroy :: proc(ctx: Context) {
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
