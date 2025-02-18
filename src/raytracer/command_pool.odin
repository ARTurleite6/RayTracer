package raytracer

// TODO: this module probably will need some refactor to be more automatic like Granite Renderer

import "core:log"
import "core:strings"
import "core:sync"
import vk "vendor:vulkan"

Command_Pool :: struct {
	name:              string,
	handle:            vk.CommandPool,
	primary_buffers:   [dynamic]Command_Buffer,
	secondary_buffers: [dynamic]Command_Buffer,
}

@(require_results)
make_command_pool :: proc(
	device: Device,
	name: string,
	allocator := context.allocator,
) -> (
	pool: Command_Pool,
	result: vk.Result,
) {
	graphics_index := device_get_graphics_queue_index(device)
	assert(graphics_index != nil, "Vulkan: graphics queue should not be nil")
	create_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {},
		queueFamilyIndex = graphics_index.?,
	}

	log.infof("Application: creating command pool for thread %d", sync.current_thread_id())

	vk.CreateCommandPool(device.handle, &create_info, nil, &pool.handle) or_return
	pool.name = strings.clone(name, allocator)

	pool.primary_buffers = make([dynamic]Command_Buffer, allocator)
	pool.secondary_buffers = make([dynamic]Command_Buffer, allocator)

	return
}

@(require_results)
command_pool_allocate_primary_buffer :: proc(
	device: Device,
	command_pool: ^Command_Pool,
	name: string,
	allocator := context.allocator,
) -> (
	buffer: Command_Buffer,
	result: vk.Result,
) {
	return _command_pool_allocate(
		device,
		command_pool.handle,
		.PRIMARY,
		&command_pool.primary_buffers,
		name,
	)
}

@(require_results)
command_pool_allocate_secondary_buffer :: proc(
	device: Device,
	command_pool: ^Command_Pool,
	name: string,
	allocator := context.allocator,
) -> (
	buffer: Command_Buffer,
	result: vk.Result,
) {
	return _command_pool_allocate(
		device,
		command_pool.handle,
		.SECONDARY,
		&command_pool.primary_buffers,
		name,
	)
}

@(require_results)
command_pool_reset :: proc(command_pool: Command_Pool, device: Device) -> vk.Result {
	//TODO: Investigate the flags for release resources
	return vk.ResetCommandPool(device.handle, command_pool.handle, {})
}

delete_command_pool :: proc(command_pool: Command_Pool, device: Device) {
	_delete_buffers(command_pool.primary_buffers[:], command_pool, device)
	_delete_buffers(command_pool.secondary_buffers[:], command_pool, device)

	delete(command_pool.name)
	vk.DestroyCommandPool(device.handle, command_pool.handle, nil)
}

@(private = "file")
_delete_buffers :: proc(buffers: []Command_Buffer, command_pool: Command_Pool, device: Device) {
	for &b in buffers {
		delete(b.name)
		vk.FreeCommandBuffers(device.handle, command_pool.handle, 1, &b.handle)
	}
}

@(private = "file")
@(require_results)
_command_pool_allocate :: proc(
	device: Device,
	command_pool_handle: vk.CommandPool,
	level: vk.CommandBufferLevel,
	buffers_arr: ^[dynamic]Command_Buffer,
	name: string,
	allocator := context.allocator,
) -> (
	buffer: Command_Buffer,
	result: vk.Result,
) {
	allocate_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool_handle,
		level              = level,
		commandBufferCount = 1,
	}

	vk.AllocateCommandBuffers(device.handle, &allocate_info, &buffer.handle) or_return
	buffer.name = strings.clone(name, allocator)

	append(buffers_arr, buffer)

	return
}
