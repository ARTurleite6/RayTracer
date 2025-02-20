package raytracer

import vkb "external:odin-vk-bootstrap"
import vk "vendor:vulkan"

Fence :: struct {
	ptr:    vk.Fence,
	device: ^vkb.Device,
}

Semaphore :: struct {
	ptr:    vk.Semaphore,
	device: ^vkb.Device,
}

@(require_results)
make_fence :: proc(device: ^vkb.Device, signaled := false) -> (fence: Fence, ok: bool) {
	create_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}

	if signaled do create_info.flags = {.SIGNALED}

	vk_must(vk.CreateFence(device.ptr, &create_info, nil, &fence.ptr), "Failed to create fence")
	fence.device = device
	ok = true
	return
}

@(require_results)
fence_wait :: proc(fence: ^Fence, timeout := max(u64)) -> bool {
	return vk_check(
		vk.WaitForFences(fence.device.ptr, 1, &fence.ptr, true, timeout),
		"Error while waitign on fences",
	)
}

@(require_results)
fence_reset :: proc(fence: ^Fence) -> (ok: bool) {
	return vk_check(vk.ResetFences(fence.device.ptr, 1, &fence.ptr), "Error while reseting fences")
}

@(require_results)
make_semaphore :: proc(device: ^vkb.Device) -> (semaphore: Semaphore, ok: bool) {
	create_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	vk_must(
		vk.CreateSemaphore(device.ptr, &create_info, nil, &semaphore.ptr),
		"Failed to create semaphore",
	)
	semaphore.device = device
	ok = true
	return
}

delete_fence :: proc(fence: Fence) {
	vk.DestroyFence(fence.device.ptr, fence.ptr, nil)
}

delete_semaphore :: proc(semaphore: Semaphore) {
	vk.DestroySemaphore(semaphore.device.ptr, semaphore.ptr, nil)
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

image_transition :: proc(cmd: Command_Buffer, transition: Image_Transition) {
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
	vk.CmdPipelineBarrier2(cmd.handle, &dependency_info)
}
