package raytracer

import vk "vendor:vulkan"

Command_Pool :: struct {
	pool:              vk.CommandPool,
	buffers:           [dynamic]vk.CommandBuffer,
	secondary_buffers: [dynamic]vk.CommandBuffer,
	index:             u32,
	secondary_index:   u32,
	device:            ^Device,
}

command_pool_init :: proc(pool: ^Command_Pool, device: ^Device, queue_family_index: u32) {
	pool.device = device
	create_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.TRANSIENT},
		queueFamilyIndex = queue_family_index,
	}

	_ = vk_check(
		vk.CreateCommandPool(device.logical_device.ptr, &create_info, nil, &pool.pool),
		"Failed to create command pool",
	)
}

command_pool_destroy :: proc(pool: ^Command_Pool) {
	vk.DestroyCommandPool(pool.device.logical_device.ptr, pool.pool, nil)

	// TODO: free command buffers

	delete(pool.buffers)
	delete(pool.secondary_buffers)
}

command_pool_begin :: proc(pool: ^Command_Pool) {
	assert(pool.pool != 0)

	if pool.index > 0 || pool.secondary_index > 0 {
		vk.ResetCommandPool(pool.device.logical_device.ptr, pool.pool, {})
	}

	pool.index = 0
	pool.secondary_index = 0
}

command_pool_request_command_buffer :: proc(pool: ^Command_Pool) -> vk.CommandBuffer {
	create_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = pool.pool,
		commandBufferCount = 1,
		level              = .PRIMARY,
	}

	cmd: vk.CommandBuffer
	vk.AllocateCommandBuffers(pool.device.logical_device.ptr, &create_info, &cmd)

	append(&pool.buffers, cmd)
	pool.index += 1

	return cmd
}
