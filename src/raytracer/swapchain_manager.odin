package raytracer

import "core:fmt"
import vkb "external:odin-vk-bootstrap"
import vk "vendor:vulkan"
_ :: fmt

Swapchain_Manager :: struct {
	device:        ^Device,
	handle:        ^vkb.Swapchain,
	surface:       vk.SurfaceKHR,
	frame_manager: Frame_Manager,
	images:        []vk.Image,
	image_views:   []vk.ImageView,
	extent:        vk.Extent2D,
	format:        vk.Format,
	present_mode:  vk.PresentModeKHR,
	current_image: u32,
}

Swapchain_Config :: struct {
	extent:         vk.Extent2D,
	preferred_mode: vk.PresentModeKHR,
	vsync:          bool,
}

Swapchain_Error :: union {
	Swapchain_Specific_Error,
	Frame_Error,
}

Swapchain_Specific_Error :: enum {
	None = 0,
	Creation_Failed,
	Image_Acquisition_Failed,
	Image_View_Creation_Failed,
	Invalid_Surface,
	Out_Of_Date,
	Suboptimal_Surface,
}

Image_Transition :: struct {
	image:      vk.Image,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
	src_stage:  vk.PipelineStageFlags2,
	dst_stage:  vk.PipelineStageFlags2,
	src_access: vk.AccessFlags2,
	dst_access: vk.AccessFlags2,
}

swapchain_manager_init :: proc(
	manager: ^Swapchain_Manager,
	device: ^Device,
	surface: vk.SurfaceKHR,
	config: Swapchain_Config,
	allocator := context.allocator,
) -> (
	err: Swapchain_Error,
) {
	if surface == 0 {
		return .Invalid_Surface
	}

	manager.device = device
	manager.surface = surface

	if create_err := swapchain_init(manager, config, resizing = false, allocator = allocator);
	   create_err != nil {
		// TODO: DESTROY swapchain
		return create_err
	}

	return nil
}

@(private)
swapchain_init :: proc(
	manager: ^Swapchain_Manager,
	config: Swapchain_Config,
	resizing: bool,
	allocator := context.allocator,
) -> Swapchain_Error {
	builder, ok := vkb.init_swapchain_builder(manager.device.logical_device)
	if !ok {
		return .Creation_Failed
	}

	defer vkb.destroy_swapchain_builder(&builder)

	vkb.swapchain_builder_set_old_swapchain(&builder, manager.handle)
	vkb.swapchain_builder_set_desired_extent(&builder, config.extent.width, config.extent.height)
	vkb.swapchain_builder_use_default_format_selection(&builder)

	if config.vsync {
		vkb.swapchain_builder_set_present_mode(&builder, .FIFO)
	} else {
		vkb.swapchain_builder_set_present_mode(&builder, config.preferred_mode)
	}

	ok = false
	if manager.handle, ok = vkb.build_swapchain(&builder); !ok {
		return .Creation_Failed
	}

	ok = false

	if manager.images, ok = vkb.swapchain_get_images(manager.handle, allocator = allocator); !ok {
		return .Image_Acquisition_Failed
	}

	if manager.image_views, ok = vkb.swapchain_get_image_views(
		manager.handle,
		allocator = allocator,
	); !ok {
		return .Image_View_Creation_Failed
	}

	manager.extent = manager.handle.extent
	manager.format = manager.handle.image_format
	manager.present_mode = manager.handle.present_mode

	if resizing {
		frame_manager_handle_resize(&manager.frame_manager) or_return
	} else {
		frame_manager_init(&manager.frame_manager, manager.device) or_return
	}

	return nil
}

swapchain_manager_destroy :: proc(manager: ^Swapchain_Manager) {
	frame_manager_destroy(&manager.frame_manager)
	vkb.swapchain_destroy_image_views(manager.handle, manager.image_views)
	vkb.destroy_swapchain(manager.handle)
}

swapchain_manager_submit_command_buffers :: proc(
	manager: ^Swapchain_Manager,
	command_buffers: []vk.CommandBuffer,
) -> Swapchain_Error {
	frame := frame_manager_get_frame(&manager.frame_manager)
	{ 	// submit to graphics queue
		submit_info := vk.SubmitInfo {
			sType                = .SUBMIT_INFO,
			waitSemaphoreCount   = 1,
			pWaitSemaphores      = &frame.sync.image_available,
			pWaitDstStageMask    = raw_data(
				[]vk.PipelineStageFlags{{vk.PipelineStageFlag.COLOR_ATTACHMENT_OUTPUT}},
			),
			commandBufferCount   = u32(len(command_buffers)),
			pCommandBuffers      = raw_data(command_buffers),
			signalSemaphoreCount = 1,
			pSignalSemaphores    = &frame.sync.render_finished,
		}
		_ = vk_check(
			vk.QueueSubmit(
				manager.device.graphics_queue,
				1,
				&submit_info,
				frame.sync.in_flight_fence,
			),
			"Failed to submit to graphics queue",
		)
	}

	{ 	// present
		present_info := vk.PresentInfoKHR {
			sType              = .PRESENT_INFO_KHR,
			waitSemaphoreCount = 1,
			pWaitSemaphores    = &frame.sync.render_finished,
			swapchainCount     = 1,
			pSwapchains        = &manager.handle.ptr,
			pImageIndices      = &manager.current_image,
		}

		result := vk_check(
			vk.QueuePresentKHR(manager.device.present_queue, &present_info),
			"Failed to present",
		)
		#partial switch result {
		case .SUCCESS:
		case .ERROR_OUT_OF_DATE_KHR:
			return .Out_Of_Date
		case .SUBOPTIMAL_KHR:
			return .Suboptimal_Surface
		}

		frame_manager_advance(&manager.frame_manager)
	}

	return nil
}

swapchain_manager_get_current_image_info :: proc(
	manager: Swapchain_Manager,
) -> (
	image: vk.Image,
	image_view: vk.ImageView,
) {
	curr_image := manager.current_image
	return manager.images[curr_image], manager.image_views[curr_image]
}

swapchain_recreate :: proc(
	manager: ^Swapchain_Manager,
	new_width, new_height: u32,
	allocator := context.allocator,
) -> (
	err: Swapchain_Error,
) {
	_ = vk_check(vk.DeviceWaitIdle(manager.device.logical_device.ptr), "Failed to wait on device")

	old_swapchain := manager.handle
	old_images := manager.images
	old_image_views := manager.image_views
	defer if old_swapchain != nil {
		vkb.swapchain_destroy_image_views(old_swapchain, old_image_views)
		delete(old_images)
		delete(old_image_views)
		vkb.destroy_swapchain(old_swapchain)
	}

	config := Swapchain_Config {
		extent = {width = new_width, height = new_height},
		preferred_mode = manager.present_mode,
		vsync = manager.present_mode == .FIFO,
	}

	if err = swapchain_init(manager, config, resizing = true, allocator = allocator); err != nil {
		return err
	}

	return nil
}

Acquire_Result :: struct {
	image_index: u32,
	suboptimal:  bool,
}

swapchain_acquire_next_image :: proc(
	manager: ^Swapchain_Manager,
	semaphore: vk.Semaphore,
	timeout := max(u64),
) -> (
	result: Acquire_Result,
	err: Swapchain_Error,
) {
	res := vk_check(
		vk.AcquireNextImageKHR(
			manager.device.logical_device.ptr,
			manager.handle.ptr,
			timeout,
			semaphore,
			0,
			&result.image_index,
		),
		"Failed to acquire next image",
	)

	#partial switch res {
	case .SUCCESS:
		manager.current_image = result.image_index
		return result, nil
	case .SUBOPTIMAL_KHR:
		result.suboptimal = true
		return result, nil
	case .ERROR_OUT_OF_DATE_KHR:
		return {}, .Out_Of_Date
	case:
		return {}, .Image_Acquisition_Failed
	}

	return
}

image_transition :: proc(cmd: vk.CommandBuffer, transition: Image_Transition) {
	barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = transition.src_stage,
		srcAccessMask = transition.src_access,
		dstStageMask = transition.dst_stage,
		dstAccessMask = transition.dst_access,
		oldLayout = transition.old_layout,
		newLayout = transition.new_layout,
		image = transition.image,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	dependency_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
	}
	vk.CmdPipelineBarrier2(cmd, &dependency_info)
}
