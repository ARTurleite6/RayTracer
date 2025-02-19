package raytracer

import vk "vendor:vulkan"
import "core:fmt"

Fence :: vk.Fence

Semaphore :: vk.Semaphore

@(require_results)
make_fence :: proc(device: Device, signaled := false) -> (fence: Fence, result: vk.Result) {
	create_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
	}

	if signaled do create_info.flags = {.SIGNALED}

	fmt.println("OLA")
	vk.CreateFence(device.handle, &create_info, nil, &fence) or_return
	return
}

@(require_results)
fence_wait :: proc(fence: ^Fence, device: Device, timeout := max(u64)) -> vk.Result {
	return vk.WaitForFences(device.handle, 1, fence, true, timeout)
}

@(require_results)
fence_reset :: proc(fence: ^Fence, device: Device) -> vk.Result {
	return vk.ResetFences(device.handle, 1, fence)
}

@(require_results)
make_semaphore :: proc(device: Device) -> (fence: Semaphore, result: vk.Result) {
	create_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	vk.CreateSemaphore(device.handle, &create_info, nil, &fence) or_return
	return
}

delete_fence :: proc(fence: Fence, device: Device) {
	vk.DestroyFence(device.handle, fence, nil)
}

delete_semaphore :: proc(semaphore: Semaphore, device: Device) {
	vk.DestroySemaphore(device.handle, semaphore, nil)
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
