package raytracer

import "base:runtime"
import "core:slice"
import "vendor:glfw"
import vk "vendor:vulkan"
_ :: slice

g_context: runtime.Context

Context :: struct {
	instance: Instance,
	debugger: Debugger,
}

Context_Error :: union #shared_nil {
	vk.Result,
}


@(require_results)
make_context :: proc() -> (ctx: Context, err: Context_Error) {
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

	vk.load_proc_addresses(ctx.instance)
	when ODIN_DEBUG {
	   ctx.debugger = make_debugger(ctx.instance) or_return
	}

	return
}

delete_context :: proc(ctx: Context) {
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
