package raytracer

import "core:log"
import "core:sync"
import vk "vendor:vulkan"

Command_Pool :: struct {
	name:    string,
	handle:  vk.CommandPool,
	buffers: []Command_Buffer,
}

make_command_pool :: proc(
	device: Device,
	name: string,
) -> (
	pool: Command_Pool,
	result: vk.Result,
) {
	graphics_index := device_get_graphics_queue_index(device)
	assert(graphics_index != nil, "Vulkan: graphics queue should not be nil")
	create_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.TRANSIENT, .RESET_COMMAND_BUFFER},
		queueFamilyIndex = graphics_index.?,
	}

	log.infof("Application: creating command pool for thread %d", sync.current_thread_id)

	vk.CreateCommandPool(device.handle, &create_info, nil, &pool.handle) or_return
	pool.name = name

	return
}

delete_command_pool :: proc(command_pool: Command_Pool, device: Device) {
    vk.DestroyCommandPool(device.handle, command_pool.handle, nil)
}
