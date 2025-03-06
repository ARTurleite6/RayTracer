package raytracer

import "core:fmt"
import vkb "external:odin-vk-bootstrap"
import vk "vendor:vulkan"
_ :: fmt

MAX_FRAMES_IN_FLIGHT :: 1

Vulkan_Error :: union {
	Device_Error,
	Swapchain_Error,
	Frame_Error,
}

Frame_Error :: enum {
	None = 0,
	Command_Pool_Creation_Failed,
	Command_Buffer_Creation_Failed,
	Descriptor_Set_Creation_Failed,
	Buffer_Creation_Failed,
	Sync_Creation_Failed,
}

Vulkan_Context :: struct {
	device:                ^Device,
	swapchain_manager:     Swapchain_Manager,
	descriptor_pool:       vk.DescriptorPool,
	descriptor_manager:    Descriptor_Set_Manager,
	//frames
	frames:                [MAX_FRAMES_IN_FLIGHT]Frame_Data,
	current_frame:         int,

	// raytracing images
	raytracing_image:      Image,
	raytracing_image_view: vk.ImageView,
}

Frame_Data :: struct {
	command_pool:    vk.CommandPool,
	primary_buffer:  vk.CommandBuffer,
	render_finished: vk.Semaphore,
	image_available: vk.Semaphore,
	in_flight_fence: vk.Fence,

	// Uniform Buffer
	uniform_buffer:  Buffer,
}

vulkan_context_init :: proc(
	ctx: ^Vulkan_Context,
	window: ^Window,
	allocator := context.allocator,
) -> (
	err: Vulkan_Error,
) {
	ctx.device = new(Device)
	device_init(ctx.device, window, allocator) or_return

	surface, _ := window_get_surface(window, ctx.device.instance)
	swapchain_manager_init(
		&ctx.swapchain_manager,
		ctx.device,
		surface,
		{extent = window_get_extent(window^), vsync = true},
	) or_return

	frames_data_init(ctx) or_return

	descriptor_pool_init(
		&ctx.descriptor_pool,
		ctx.device,
		{{.UNIFORM_BUFFER, MAX_FRAMES_IN_FLIGHT}},
		1000,
	)
	descriptor_manager_init(&ctx.descriptor_manager, ctx.device, ctx.descriptor_pool, allocator)

	ctx_descriptor_sets_init(ctx)

	{
		image_init(&ctx.raytracing_image, ctx, .B8G8R8A8_UNORM, ctx.swapchain_manager.extent)
		image_view_init(&ctx.raytracing_image_view, ctx.raytracing_image, ctx)

		cmd := device_begin_single_time_commands(ctx.device, ctx.device.command_pool)
		defer device_end_single_time_commands(ctx.device, ctx.device.command_pool, cmd)
		image_transition_layout_stage_access(
			cmd,
			ctx.raytracing_image.handle,
			.UNDEFINED,
			.GENERAL,
			{.ALL_COMMANDS},
			{.ALL_COMMANDS},
			{},
			{},
		)
	}

	return nil
}

ctx_destroy :: proc(ctx: ^Vulkan_Context) {
	descriptor_manager_destroy(&ctx.descriptor_manager)

	frames_data_destroy(ctx)

	for &f in ctx.frames {
		buffer_destroy(&f.uniform_buffer, ctx.device)
	}

	swapchain_manager_destroy(&ctx.swapchain_manager)

	device_destroy(ctx.device)
}

ctx_create_rt_descriptor_set :: proc(ctx: ^Vulkan_Context, tlas: ^vk.AccelerationStructureKHR) {
	layout: Descriptor_Set_Layout

	descriptor_set_layout_init(
		&layout,
		ctx.device,
		{
			{ 	// TLAS
				binding         = 0,
				descriptorType  = .ACCELERATION_STRUCTURE_KHR,
				descriptorCount = 1,
				stageFlags      = {.RAYGEN_KHR},
			},
			{ 	// Output Image
				binding         = 1,
				descriptorType  = .STORAGE_IMAGE,
				descriptorCount = 1,
				stageFlags      = {.RAYGEN_KHR},
			},
		},
	)

	descriptor_manager_register_descriptor_sets(&ctx.descriptor_manager, "raytracing_main", layout)
	descriptor_manager_write_acceleration_structure(
		&ctx.descriptor_manager,
		"raytracing_main",
		0,
		0,
		tlas,
	)
	descriptor_manager_write_image(
		&ctx.descriptor_manager,
		"raytracing_main",
		0,
		1,
		ctx.raytracing_image_view,
	)

}

ctx_begin_frame :: proc(
	ctx: ^Vulkan_Context,
) -> (
	cmd: vk.CommandBuffer,
	image_index: u32,
	err: Render_Error,
) {
	frame := &ctx.frames[ctx.current_frame]
	device := ctx.device.logical_device.ptr

	_ = vk_check(
		vk.WaitForFences(device, 1, &frame.in_flight_fence, true, max(u64)),
		"Failed to wait on frame fences",
	)

	result := swapchain_acquire_next_image(&ctx.swapchain_manager, frame.image_available) or_return

	_ = vk_check(
		vk.ResetFences(device, 1, &frame.in_flight_fence),
		"Error reseting in_flight_fence",
	)

	cmd = frame.primary_buffer
	_ = vk_check(vk.ResetCommandBuffer(cmd, {}), "Error reseting command buffer")

	return cmd, result.image_index, nil
}

ctx_update_uniform_buffer :: proc(ctx: ^Vulkan_Context, data: rawptr) {
	buffer := &ctx.frames[ctx.current_frame].uniform_buffer
	buffer_write(buffer, data)
	buffer_flush(buffer, ctx.device^)
}

ctx_swapchain_present :: proc(
	ctx: ^Vulkan_Context,
	command_buffer: vk.CommandBuffer,
	image_index: u32,
) -> Swapchain_Error {
	frame := &ctx.frames[ctx.current_frame]
	{ 	// submit to graphics queue
		command_buffer := command_buffer
		submit_info := vk.SubmitInfo {
			sType                = .SUBMIT_INFO,
			waitSemaphoreCount   = 1,
			pWaitSemaphores      = &frame.image_available,
			pWaitDstStageMask    = raw_data(
				[]vk.PipelineStageFlags{{vk.PipelineStageFlag.COLOR_ATTACHMENT_OUTPUT}},
			),
			commandBufferCount   = 1,
			pCommandBuffers      = &command_buffer,
			signalSemaphoreCount = 1,
			pSignalSemaphores    = &frame.render_finished,
		}
		_ = vk_check(
			vk.QueueSubmit(ctx.device.graphics_queue, 1, &submit_info, frame.in_flight_fence),
			"Failed to submit to graphics queue",
		)
	}

	{ 	// present
		image_index := image_index
		present_info := vk.PresentInfoKHR {
			sType              = .PRESENT_INFO_KHR,
			waitSemaphoreCount = 1,
			pWaitSemaphores    = &frame.render_finished,
			swapchainCount     = 1,
			pSwapchains        = &ctx.swapchain_manager.handle.ptr,
			pImageIndices      = &image_index,
		}

		result := vk_check(
			vk.QueuePresentKHR(ctx.device.present_queue, &present_info),
			"Failed to present",
		)
		#partial switch result {
		case .SUCCESS:
		case .ERROR_OUT_OF_DATE_KHR:
			return .Out_Of_Date
		case .SUBOPTIMAL_KHR:
			return .Suboptimal_Surface
		}

		ctx.current_frame = (ctx.current_frame + 1) % MAX_FRAMES_IN_FLIGHT
	}

	return nil
}

ctx_handle_resize :: proc(
	ctx: ^Vulkan_Context,
	new_width, new_height: u32,
	allocator := context.allocator,
) -> (
	err: Swapchain_Error,
) {
	_ = vk_check(vk.DeviceWaitIdle(ctx.device.logical_device.ptr), "Failed to wait on device")

	swapchain_recreate(&ctx.swapchain_manager, new_width, new_height, allocator) or_return

	frames_data_destroy(ctx)
	frames_data_init(ctx)

	return nil
}

ctx_descriptor_sets_init :: proc(ctx: ^Vulkan_Context) {
	{ 	// init uniform buffers
		for &f in ctx.frames {
			buffer_init(
				&f.uniform_buffer,
				ctx.device,
				size_of(Global_Ubo),
				1,
				{.UNIFORM_BUFFER},
				.Cpu_To_Gpu,
			)

			buffer_map(&f.uniform_buffer, ctx.device)
		}
	}

	{
		layout: Descriptor_Set_Layout
		descriptor_set_layout_init(
			&layout,
			ctx.device,
			{
				{
					binding = 0,
					descriptorType = .UNIFORM_BUFFER,
					descriptorCount = 1,
					stageFlags = {.VERTEX, .RAYGEN_KHR},
				},
			},
		)
		descriptor_manager_register_descriptor_sets(
			&ctx.descriptor_manager,
			"camera",
			layout,
			MAX_FRAMES_IN_FLIGHT,
		)
	}

	{ 	// descriptor sets
		for &f, i in ctx.frames {
			buffer := f.uniform_buffer
			descriptor_manager_write_buffer(
				&ctx.descriptor_manager,
				"camera",
				u32(i),
				0,
				buffer.handle,
				vk.DeviceSize(size_of(Global_Ubo)),
			)
		}
	}
}

frames_data_init :: proc(ctx: ^Vulkan_Context) -> Frame_Error {
	for &f in ctx.frames {
		{ 	// Create command pool and buffer
			pool_info := vk.CommandPoolCreateInfo {
				sType            = .COMMAND_POOL_CREATE_INFO,
				flags            = {.RESET_COMMAND_BUFFER},
				queueFamilyIndex = vkb.device_get_queue_index(
					ctx.device.logical_device,
					.Graphics,
				),
			}

			if result := vk_check(
				vk.CreateCommandPool(
					ctx.device.logical_device.ptr,
					&pool_info,
					nil,
					&f.command_pool,
				),
				"Failed to create command pool",
			); result != .SUCCESS {
				return .Command_Pool_Creation_Failed
			}

			buffer_info := vk.CommandBufferAllocateInfo {
				sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
				commandPool        = f.command_pool,
				level              = .PRIMARY,
				commandBufferCount = 1,
			}

			if result := vk_check(
				vk.AllocateCommandBuffers(
					ctx.device.logical_device.ptr,
					&buffer_info,
					&f.primary_buffer,
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
						ctx.device.logical_device.ptr,
						&create_info,
						nil,
						&f.in_flight_fence,
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
						ctx.device.logical_device.ptr,
						&create_info,
						nil,
						&f.image_available,
					),
					"Failed to create semaphore",
				); result != .SUCCESS {
					return .Sync_Creation_Failed
				}

				if result := vk_check(
					vk.CreateSemaphore(
						ctx.device.logical_device.ptr,
						&create_info,
						nil,
						&f.render_finished,
					),
					"Failed to create semaphore",
				); result != .SUCCESS {
					return .Sync_Creation_Failed
				}
			}
		}
	}

	return .None
}

frames_data_destroy :: proc(ctx: ^Vulkan_Context) {
	device := ctx.device.logical_device.ptr
	for &f in ctx.frames {
		vk.FreeCommandBuffers(device, f.command_pool, 1, &f.primary_buffer)
		vk.DestroyCommandPool(device, f.command_pool, nil)
		vk.DestroyFence(device, f.in_flight_fence, nil)
		vk.DestroySemaphore(device, f.image_available, nil)
		vk.DestroySemaphore(device, f.render_finished, nil)
	}
}
