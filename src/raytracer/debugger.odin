package raytracer

import "core:log"
import vk "vendor:vulkan"

Debugger :: vk.DebugUtilsMessengerEXT
DebuggerCreateInfo :: vk.DebugUtilsMessengerCreateInfoEXT

@(require_results)
make_debugger :: proc(instance: Instance) -> (debugger: Debugger, result: vk.Result) {
    create_info := debugger_info()

    result = vk.CreateDebugUtilsMessengerEXT(instance, &create_info, nil, &debugger)

    return
}

delete_debugger :: proc(debugger: Debugger, instance: Instance) {
    vk.DestroyDebugUtilsMessengerEXT(instance, debugger, nil)
}

@(require_results)
debugger_info :: proc() -> (info: DebuggerCreateInfo) {
    logger := context.logger

	info = DebuggerCreateInfo {
		sType       = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageType = {.GENERAL, .VALIDATION, .PERFORMANCE, .DEVICE_ADDRESS_BINDING},
	}

	info.pfnUserCallback = debugger_callback

	if logger.lowest_level <= .Error {
		info.messageSeverity |= {.ERROR}
	}
	if logger.lowest_level <= .Info {
		info.messageSeverity |= {.INFO}
	}
	if logger.lowest_level <= .Debug {
		info.messageSeverity |= {.VERBOSE}
	}
	if logger.lowest_level <= .Warning {
		info.messageSeverity |= {.WARNING}
	}

	return
}

@(private = "file")
debugger_callback :: proc "system" (
	message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	message_types: vk.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> b32 {
	context = g_context
	level: log.Level

	if .ERROR in message_severity {
		level = .Error
	} else if .WARNING in message_severity {
		level = .Warning
	} else if .INFO in message_severity {
		level = .Info
	} else {
		level = .Debug
	}

	log.logf(level, "Vulkan[%v]: %s", message_types, callback_data.pMessage)
	return false
}
