package raytracer

import "core:log"
import vk "vendor:vulkan"

Debugger :: vk.DebugUtilsMessengerEXT
DebuggerCreateInfo :: vk.DebugUtilsMessengerCreateInfoEXT

debugger_init :: proc(debugger: ^Debugger, instance: Instance, info: ^DebuggerCreateInfo = nil) {
	if info == nil {
		debugger_get_info(info)
	}

	vk.CreateDebugUtilsMessengerEXT(instance, info, nil, debugger)
}

debugger_destroy :: proc(debugger: Debugger, instance: Instance) {
	vk.DestroyDebugUtilsMessengerEXT(instance, debugger, nil)
}

debugger_get_info :: proc(info: ^DebuggerCreateInfo) {
	logger := context.logger
	info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
	info.pUserData = &logger
	info.pfnUserCallback = debugger_callback
	info.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE, .DEVICE_ADDRESS_BINDING}

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
}

@(private = "file")
debugger_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = g_context
	level: log.Level
	if .ERROR in messageSeverity {
		level = .Error
	} else if .WARNING in messageSeverity {
		level = .Warning
	} else if .INFO in messageSeverity {
		level = .Info
	} else {
		level = .Debug
	}

	log.log(level, "vulkan[%v]: %s", messageTypes, pCallbackData.pMessage)
	return false
}
