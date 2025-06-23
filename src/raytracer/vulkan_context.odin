#+feature dynamic-literals

package raytracer
import "core:log"

import vk "vendor:vulkan"

import vkb "external:odin-vk-bootstrap"
import vma "external:odin-vma"
_ :: log

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

BASE_BLOCK_SIZE :: 256

SUPPORTED_USAGE_MAP := map[vk.BufferUsageFlags]int {
	// Original usage types
	{.UNIFORM_BUFFER} = 1, // Base size (e.g., 1MB)
	{.STORAGE_BUFFER} = 2, // 2x base (e.g., 2MB)
	{.VERTEX_BUFFER} = 1, // Base size
	{.INDEX_BUFFER} = 1, // Base size

	// Ray tracing specific combinations
	{.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS} = 4, // 4x base (e.g., 4MB)
	{.VERTEX_BUFFER, .STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS} = 4, // RT vertex buffers
	{.INDEX_BUFFER, .STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS} = 4, // RT index buffers

	// Acceleration structure buffers (very large)
	{.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR, .SHADER_DEVICE_ADDRESS} = 8, // 8x base

	// Staging buffers
	{.TRANSFER_SRC} = 8, // Large for texture uploads
	{.TRANSFER_DST} = 2, // Medium for downloads
}

Vulkan_Context :: struct {
	device:            ^Device,
	swapchain_manager: Swapchain_Manager,
	descriptor_pool:   vk.DescriptorPool,
	//frames
	frames:            [MAX_FRAMES_IN_FLIGHT]Internal_Frame_Data,
	current_frame:     int,
	current_image:     u32,
	cache:             Resource_Cache,
}

Internal_Frame_Data :: struct {
	buffer_pools:    map[vk.BufferUsageFlags]Buffer_Pool,
	command_pool:    Command_Pool,
	render_finished: vk.Semaphore,
	image_available: vk.Semaphore,
	in_flight_fence: vk.Fence,
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

	descriptor_pool_init(
		&ctx.descriptor_pool,
		ctx.device,
		{{.UNIFORM_BUFFER, MAX_FRAMES_IN_FLIGHT}},
		1000,
	)

	resource_cache_init(ctx, allocator)

	// Initialize buffer pools
	for &f in ctx.frames {
		for key, size in SUPPORTED_USAGE_MAP {
			buffer_pool: Buffer_Pool
			memory_usage := vma.Memory_Usage.Gpu_Only
			if .TRANSFER_SRC in key || .UNIFORM_BUFFER in key {
				memory_usage = .Cpu_To_Gpu
			} else if .TRANSFER_DST in key {
				memory_usage = .Gpu_To_Cpu
			}
			buffer_pool_init(&buffer_pool, 1024 * BASE_BLOCK_SIZE * size, key, memory_usage)
			f.buffer_pools[key] = buffer_pool
		}
	}

	return nil
}

ctx_destroy :: proc(ctx: ^Vulkan_Context, allocator := context.allocator) {
	for &f in ctx.frames {
		for _, &p in f.buffer_pools {
			buffer_pool_destroy(&p)
		}
	}

	resource_cache_destroy(ctx, allocator)

	vk.DestroyDescriptorPool(ctx.device.logical_device.ptr, ctx.descriptor_pool, nil)
	frames_data_destroy(ctx)

	swapchain_manager_destroy(&ctx.swapchain_manager)

	device_destroy(ctx.device)
	free(ctx.device)
}

@(require_results)
vulkan_context_request_buffer :: proc(
	ctx: ^Vulkan_Context,
	usage_flags: vk.BufferUsageFlags,
	size: vk.DeviceSize,
) -> Buffer_Allocation {
	frame := &ctx.frames[ctx.current_frame]
	pool, found := &frame.buffer_pools[usage_flags]
	assert(found, "This usage flags are not available to cache")

	// TODO: add error handling in this implementation
	block := buffer_pool_request_buffer_block(pool, ctx, size)
	return buffer_block_allocate(block, size)
}

@(require_results)
vulkan_context_request_uniform_buffer :: proc(
	ctx: ^Vulkan_Context,
	size: vk.DeviceSize,
) -> Buffer_Allocation {
	frame := &ctx.frames[ctx.current_frame]

	// TODO: add error handling in this implementation
	block := buffer_pool_request_buffer_block(&frame.buffer_pools[{.UNIFORM_BUFFER}], ctx, size)
	return buffer_block_allocate(block, size)
}

@(require_results)
vulkan_context_request_staging_buffer :: proc(
	ctx: ^Vulkan_Context,
	size: vk.DeviceSize,
) -> Buffer_Allocation {
	frame := &ctx.frames[ctx.current_frame]

	// TODO: add error handling in this implementation
	block := buffer_pool_request_buffer_block(&frame.buffer_pools[{.TRANSFER_SRC}], ctx, size)
	return buffer_block_allocate(block, size)
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

vulkan_copy_buffer_allocation_with_staging_buffer :: proc(
	ctx: ^Vulkan_Context,
	dst: ^Buffer_Allocation,
	data: rawptr,
	size: vk.DeviceSize,
) {
	staging_buffer := vulkan_context_request_staging_buffer(ctx, size)
	buffer_allocation_update(&staging_buffer, data, size)
	device_copy_buffer(
		ctx.device,
		staging_buffer.buffer.handle,
		dst.buffer.handle,
		staging_buffer.size,
		dst.offset,
	)
}

ctx_request_command_buffer :: proc(ctx: ^Vulkan_Context) -> (cmd: Command_Buffer) {
	frame := &ctx.frames[ctx.current_frame]
	buffer := command_pool_request_command_buffer(&frame.command_pool)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	vk.BeginCommandBuffer(buffer, &begin_info)

	command_buffer_init(&cmd, buffer)
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

	for _, &p in frame.buffer_pools {
		buffer_pool_reset(&p)
	}
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
