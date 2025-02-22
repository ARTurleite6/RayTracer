package raytracer

// TODO: this module probably will need some refactor to be more automatic like Granite Renderer

import "core:fmt"
import "core:strings"
import vkb "external:odin-vk-bootstrap"
import vk "vendor:vulkan"
_ :: fmt


Command_Pool :: struct {
	name:   string,
	handle: vk.CommandPool,
	device: ^vkb.Device,
}

Command_Buffer :: struct {
	name:   string,
	handle: vk.CommandBuffer,
}

@(require_results)
make_command_pool :: proc(
	device: ^vkb.Device,
	name: string,
	flags: vk.CommandPoolCreateFlags = {},
	allocator := context.allocator,
) -> (
	pool: Command_Pool,
	err: Backend_Error,
) {
	graphics_index := vkb.device_get_queue_index(device, .Graphics)
	create_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = flags,
		queueFamilyIndex = graphics_index,
	}

	vk_check(
		vk.CreateCommandPool(device.ptr, &create_info, nil, &pool.handle),
		"Failed to create command pool:",
	) or_return
	pool.name = strings.clone(name, allocator)

	pool.device = device

	return pool, nil
}

@(require_results)
command_pool_allocate_primary_buffer :: proc(
	command_pool: ^Command_Pool,
	name: string,
	allocator := context.allocator,
) -> (
	buffer: Command_Buffer,
	err: Backend_Error,
) {
	buffer = _command_pool_allocate(
		command_pool.device,
		command_pool.handle,
		.PRIMARY,
		name,
	) or_return

	return buffer, nil
}

@(require_results)
command_pool_allocate_secondary_buffer :: proc(
	command_pool: ^Command_Pool,
	name: string,
	allocator := context.allocator,
) -> (
	Command_Buffer,
	Backend_Error,
) {
	return _command_pool_allocate(command_pool.device, command_pool.handle, .SECONDARY, name)
}

@(require_results)
command_pool_reset :: proc(command_pool: Command_Pool) -> Backend_Error {
	//TODO: Investigate the flags for release resources
	return vk_check(
		vk.ResetCommandPool(command_pool.device.ptr, command_pool.handle, {}),
		"Failed to reset command buffer",
	)
}

delete_command_pool :: proc(command_pool: ^Command_Pool) {
	delete(command_pool.name)
	vk.DestroyCommandPool(command_pool.device.ptr, command_pool.handle, nil)
}

@(require_results)
command_buffer_begin :: proc(
	command_buffer: Command_Buffer,
	flags: vk.CommandBufferUsageFlags = {},
) -> Backend_Error {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = flags,
	}
	return vk_check(
		vk.BeginCommandBuffer(command_buffer.handle, &begin_info),
		"Error while starting command buffer",
	)
}

command_buffer_end_rendering :: proc(command_buffer: Command_Buffer) {
	vk.CmdEndRendering(command_buffer.handle)
}

command_buffer_begin_rendering :: proc(
	command_buffer: Command_Buffer,
	image_view: vk.ImageView,
	extent: vk.Extent2D,
	clear_color: vk.ClearValue,
) {
	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = image_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = clear_color,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
	}

	vk.CmdBeginRendering(command_buffer.handle, &rendering_info)
}

command_buffer_reset :: proc(command_buffer: Command_Buffer) {
	vk.ResetCommandBuffer(command_buffer.handle, {.RELEASE_RESOURCES})
}

command_pool_delete_buffer :: proc(pool: Command_Pool, cmd: ^Command_Buffer) {
	vk.FreeCommandBuffers(pool.device.ptr, pool.handle, 1, &cmd.handle)
}

@(private = "file")
@(require_results)
_command_pool_allocate :: proc(
	device: ^vkb.Device,
	command_pool_handle: vk.CommandPool,
	level: vk.CommandBufferLevel,
	name: string,
	allocator := context.allocator,
) -> (
	buffer: Command_Buffer,
	err: Backend_Error,
) {
	allocate_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool_handle,
		level              = level,
		commandBufferCount = 1,
	}

	vk_must(
		vk.AllocateCommandBuffers(device.ptr, &allocate_info, &buffer.handle),
		"Failed to allocate command buffers",
	)
	buffer.name = strings.clone(name, allocator)

	return buffer, nil
}
