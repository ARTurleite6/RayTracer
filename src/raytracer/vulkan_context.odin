#+feature dynamic-literals

package raytracer
import "core:fmt"
import "core:log"
import "core:os"
import vkb "external:odin-vk-bootstrap"
import vk "vendor:vulkan"
_ :: log

MAX_FRAMES_IN_FLIGHT :: 1

Render_Error :: union {
	Pipeline_Error,
	Shader_Error,
	Swapchain_Error,
}


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
	device:            ^Device,
	device_properties: vk.PhysicalDeviceProperties,
	swapchain_manager: Swapchain_Manager,
	// descriptor_pool:   vk.DescriptorPool,
	//frames
	frames:            [MAX_FRAMES_IN_FLIGHT]Internal_Frame_Data,
	current_frame:     int,
	current_image:     u32,
	cache:             Resource_Cache,
}

Internal_Frame_Data :: struct {
	ubo_buffer_pool, staging_buffer_pool, storage_buffer_pool: Buffer_Pool,
	command_pool:                                              Command_Pool,
	render_finished:                                           vk.Semaphore,
	image_available:                                           vk.Semaphore,
	in_flight_fence:                                           vk.Fence,
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
		{
			extent = {width = u32(window.width), height = u32(window.height)},
			preferred_mode = .MAILBOX,
		},
	) or_return

	frames_data_init(ctx) or_return

	resource_cache_init(ctx, allocator)

	for &f in ctx.frames {
		buffer_pool_init(
			&f.ubo_buffer_pool,
			1024 * 4,
			{.UNIFORM_BUFFER},
			.Cpu_To_Gpu,
			alignment = ctx.device.physical_device.properties.limits.minUniformBufferOffsetAlignment,
			allocator = allocator,
		)
		buffer_pool_init(
			&f.staging_buffer_pool,
			1024 * 4,
			{.TRANSFER_SRC},
			.Cpu_To_Gpu,
			allocator = allocator,
		)
		buffer_pool_init(
			&f.storage_buffer_pool,
			1024 * 4,
			{.STORAGE_BUFFER},
			.Cpu_To_Gpu,
			alignment = ctx.device.physical_device.properties.limits.minStorageBufferOffsetAlignment,
			allocator = allocator,
		)
	}

	return nil
}

vulkan_context_destroy :: proc(ctx: ^Vulkan_Context, allocator := context.allocator) {
	for &f in ctx.frames {
		buffer_pool_destroy(&f.ubo_buffer_pool)
		buffer_pool_destroy(&f.staging_buffer_pool)
		buffer_pool_destroy(&f.storage_buffer_pool)
	}

	resource_cache_destroy(ctx, allocator)

	frames_data_destroy(ctx)

	swapchain_manager_destroy(&ctx.swapchain_manager)

	device_destroy(ctx.device)
	free(ctx.device)
}

vulkan_context_device_wait_idle :: proc(ctx: Vulkan_Context) {
	vk.DeviceWaitIdle(ctx.device.logical_device.ptr)
}

@(require_results)
vulkan_context_request_staging_buffer :: proc(
	ctx: ^Vulkan_Context,
	size: vk.DeviceSize,
) -> Buffer_Allocation {
	frame := &ctx.frames[ctx.current_frame]

	// TODO: add error handling in this implementation
	pool := &frame.staging_buffer_pool
	block := buffer_pool_request_buffer_block(pool, ctx, size)
	return buffer_block_allocate(block, pool.alignment, size)
}

@(require_results)
vulkan_get_device_handle :: proc(ctx: ^Vulkan_Context) -> vk.Device {
	return ctx.device.logical_device.ptr
}

@(require_results)
vulkan_get_raytracing_pipeline_properties :: proc(
	ctx: ^Vulkan_Context,
) -> (
	props: vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
) {
	props.sType = .PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_PROPERTIES_KHR
	properties := vk.PhysicalDeviceProperties2 {
		sType = .PHYSICAL_DEVICE_PROPERTIES_2,
		pNext = &props,
	}
	vk.GetPhysicalDeviceProperties2(ctx.device.physical_device.ptr, &properties)

	return props
}

ctx_request_command_buffer :: proc(ctx: ^Vulkan_Context) -> (cmd: Command_Buffer) {
	frame := &ctx.frames[ctx.current_frame]
	buffer := command_pool_request_command_buffer(&frame.command_pool)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	vk.BeginCommandBuffer(buffer, &begin_info)

	command_buffer_init(&cmd, ctx, buffer)
	return cmd
}

@(require_results)
ctx_get_swapchain_render_pass :: proc(
	ctx: Vulkan_Context,
	clear_value: Vec4 = {},
	load_op: vk.AttachmentLoadOp = .CLEAR,
	store_op: vk.AttachmentStoreOp = .STORE,
) -> vk.RenderingInfo {
	image_view := ctx.swapchain_manager.image_views[ctx.current_image]

	// TODO: probably find a more suitable way of doing this without allocating memory
	color_attachment := new(vk.RenderingAttachmentInfo, context.temp_allocator)
	color_attachment^ = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = image_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = load_op,
		storeOp = store_op,
		clearValue = {color = {float32 = clear_value}},
	}

	return vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = ctx.swapchain_manager.extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = color_attachment,
	}
}

ctx_transition_swapchain_image :: proc(
	ctx: Vulkan_Context,
	cmd: Command_Buffer,
	old_layout, new_layout: vk.ImageLayout,
	src_stage, dst_stage: vk.PipelineStageFlags2,
	src_access, dst_access: vk.AccessFlags2,
) {
	image_transition(
		cmd.buffer,
		image = ctx.swapchain_manager.images[ctx.current_image],
		old_layout = old_layout,
		new_layout = new_layout,
		src_stage = src_stage,
		dst_stage = dst_stage,
		src_access = src_access,
		dst_access = dst_access,
	)
}

ctx_begin_frame :: proc(ctx: ^Vulkan_Context) -> (image_index: u32, err: Render_Error) {
	frame := &ctx.frames[ctx.current_frame]
	device := ctx.device.logical_device.ptr

	_ = vk_check(
		vk.WaitForFences(device, 1, &frame.in_flight_fence, true, max(u64)),
		"Failed to wait on frame fences",
	)

	result := swapchain_acquire_next_image(&ctx.swapchain_manager, frame.image_available) or_return
	ctx.current_image = result.image_index

	_ = vk_check(
		vk.ResetFences(device, 1, &frame.in_flight_fence),
		"Error reseting in_flight_fence",
	)

	buffer_pool_reset(&frame.ubo_buffer_pool)
	buffer_pool_reset(&frame.storage_buffer_pool)
	buffer_pool_reset(&frame.staging_buffer_pool)

	command_pool_begin(&frame.command_pool)

	return result.image_index, nil
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

frames_data_init :: proc(ctx: ^Vulkan_Context) -> Frame_Error {
	graphics_queue_index := vkb.device_get_queue_index(ctx.device.logical_device, .Graphics)

	for &f in ctx.frames {
		{ 	// Create command pool and buffer
			command_pool_init(&f.command_pool, ctx.device, graphics_queue_index)
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
		// TODO: handle destroying buffers
		command_pool_destroy(&f.command_pool)
		vk.DestroyFence(device, f.in_flight_fence, nil)
		vk.DestroySemaphore(device, f.image_available, nil)
		vk.DestroySemaphore(device, f.render_finished, nil)
	}
}

@(private)
@(require_results)
vk_check :: proc(result: vk.Result, message: string) -> vk.Result {
	if result != .SUCCESS {
		log.errorf(fmt.tprintf("%s: \x1b[31m%v\x1b[0m", message, result))
		os.exit(1)
		// return result
	}
	return nil
}
