package raytracer

import "core:fmt"
import vkb "external:odin-vk-bootstrap"
import vk "vendor:vulkan"
_ :: fmt

MAX_FRAMES_IN_FLIGHT :: 1

Frame_Manager :: struct {
	device:        ^Device,
	frames:        [MAX_FRAMES_IN_FLIGHT]Frame,
	current_frame: int,
}

Frame :: struct {
	resources: Frame_Resources,
	commands:  Frame_Commands,
	sync:      Frame_Sync,
}

Frame_Resources :: struct {
}

Frame_Commands :: struct {
	pool:           vk.CommandPool,
	primary_buffer: vk.CommandBuffer,
}

Frame_Sync :: struct {
	render_finished: vk.Semaphore,
	image_available: vk.Semaphore,
	in_flight_fence: vk.Fence,
}

Frame_Error :: enum {
	None = 0,
	Command_Pool_Creation_Failed,
	Command_Buffer_Creation_Failed,
	Descriptor_Pool_Creation_Failed,
	Descriptor_Set_Creation_Failed,
	Buffer_Creation_Failed,
	Sync_Creation_Failed,
}

frame_manager_init :: proc(manager: ^Frame_Manager, device: ^Device) -> Frame_Error {
	manager.device = device

	for &frame in manager.frames {
		frame_init(&frame, device) or_return
	}

	return .None
}

frame_manager_destroy :: proc(manager: ^Frame_Manager) {
	for &frame in manager.frames {
		frame_destroy(&frame, manager.device)
	}
}

frame_manager_get_frame :: proc(manager: ^Frame_Manager) -> ^Frame {
	return &manager.frames[manager.current_frame]
}

frame_manager_advance :: proc(manager: ^Frame_Manager) {
	manager.current_frame = (manager.current_frame + 1) % MAX_FRAMES_IN_FLIGHT
}

frame_init :: proc(frame: ^Frame, device: ^Device) -> Frame_Error {

	{ 	// Create command pool and buffer
		pool_info := vk.CommandPoolCreateInfo {
			sType            = .COMMAND_POOL_CREATE_INFO,
			flags            = {.RESET_COMMAND_BUFFER},
			queueFamilyIndex = vkb.device_get_queue_index(device.logical_device, .Graphics),
		}

		if result := vk_check(
			vk.CreateCommandPool(device.logical_device.ptr, &pool_info, nil, &frame.commands.pool),
			"Failed to create command pool",
		); result != .SUCCESS {
			return .Command_Pool_Creation_Failed
		}

		buffer_info := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = frame.commands.pool,
			level              = .PRIMARY,
			commandBufferCount = 1,
		}

		if result := vk_check(
			vk.AllocateCommandBuffers(
				device.logical_device.ptr,
				&buffer_info,
				&frame.commands.primary_buffer,
			),
			"Failed to Allocate command buffer",
		); result != .SUCCESS {
			return .Command_Buffer_Creation_Failed
		}
	}

	{ 	// Create sync objects
		{ 	// create fence
			create_info := vk.FenceCreateInfo {
				sType = .FENCE_CREATE_INFO,
				flags = {.SIGNALED},
			}
			if result := vk_check(
				vk.CreateFence(
					device.logical_device.ptr,
					&create_info,
					nil,
					&frame.sync.in_flight_fence,
				),
				"Failed to create fence",
			); result != .SUCCESS {
				return .Sync_Creation_Failed
			}
		}
		{ 	// create semaphores
			create_info := vk.SemaphoreCreateInfo {
				sType = .SEMAPHORE_CREATE_INFO,
			}
			if result := vk_check(
				vk.CreateSemaphore(
					device.logical_device.ptr,
					&create_info,
					nil,
					&frame.sync.image_available,
				),
				"Failed to create semaphore",
			); result != .SUCCESS {
				return .Sync_Creation_Failed
			}

			if result := vk_check(
				vk.CreateSemaphore(
					device.logical_device.ptr,
					&create_info,
					nil,
					&frame.sync.render_finished,
				),
				"Failed to create semaphore",
			); result != .SUCCESS {
				return .Sync_Creation_Failed
			}
		}
	}

	return .None
}

frame_destroy :: proc(frame: ^Frame, device: ^Device) {
	vk.FreeCommandBuffers(
		device.logical_device.ptr,
		frame.commands.pool,
		1,
		&frame.commands.primary_buffer,
	)
	vk.DestroyCommandPool(device.logical_device.ptr, frame.commands.pool, nil)
	vk.DestroyFence(device.logical_device.ptr, frame.sync.in_flight_fence, nil)
	vk.DestroySemaphore(device.logical_device.ptr, frame.sync.image_available, nil)
	vk.DestroySemaphore(device.logical_device.ptr, frame.sync.render_finished, nil)
}

frame_manager_handle_resize :: proc(manager: ^Frame_Manager) -> Frame_Error {
	manager.current_frame = 0
	for &frame in manager.frames {
		// TODO: this needs to be refactored in the future
		frame_destroy(&frame, manager.device)
		frame_init(&frame, manager.device) or_return
	}
	return .None
}

frame_wait :: proc(frame: ^Frame, device: ^Device) {
	_ = vk_check(
		vk.WaitForFences(
			device.logical_device.ptr,
			1,
			&frame.sync.in_flight_fence,
			true,
			max(u64),
		),
		"Failed to wait on fences",
	)
}
