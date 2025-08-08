package raytracer

import vk "vendor:vulkan"

Command_Pool :: struct {
	pool:              vk.CommandPool,
	buffers:           [dynamic]vk.CommandBuffer,
	secondary_buffers: [dynamic]vk.CommandBuffer,
	index:             int,
	secondary_index:   int,
	device:            ^Device,
}

command_pool_init :: proc(pool: ^Command_Pool, device: ^Device, queue_family_index: u32) {
	pool.device = device
	create_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.TRANSIENT, .RESET_COMMAND_BUFFER},
		queueFamilyIndex = queue_family_index,
	}

	_ = vk_check(
		vk.CreateCommandPool(device.logical_device.ptr, &create_info, nil, &pool.pool),
		"Failed to create command pool",
	)
}

command_pool_destroy :: proc(pool: ^Command_Pool) {
	vk.DestroyCommandPool(pool.device.logical_device.ptr, pool.pool, nil)

	delete(pool.buffers)
	delete(pool.secondary_buffers)

	pool^ = {}
}

command_pool_begin :: proc(pool: ^Command_Pool) {
	assert(pool.pool != 0)

	if pool.index > 0 || pool.secondary_index > 0 {
		vk.ResetCommandPool(pool.device.logical_device.ptr, pool.pool, {})
	}

	pool.index = 0
	pool.secondary_index = 0
}

command_pool_request_command_buffer :: proc(pool: ^Command_Pool) -> (cmd: vk.CommandBuffer) {
	if pool.index < len(pool.buffers) {
		cmd = pool.buffers[pool.index]
	} else {
		create_info := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = pool.pool,
			commandBufferCount = 1,
			level              = .PRIMARY,
		}
		vk.AllocateCommandBuffers(pool.device.logical_device.ptr, &create_info, &cmd)
		append(&pool.buffers, cmd)
	}
	pool.index += 1

	return cmd
}
