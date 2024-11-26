package raytracer

import vk "vendor:vulkan"

Fence :: vk.Fence

@(require_results)
fence_init :: proc(
	fence: ^Fence,
	device: Device,
	flags: vk.FenceCreateFlags = {.SIGNALED},
) -> vk.Result {
	create_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	return vk.CreateFence(device, &create_info, nil, fence)
}

fence_destroy :: proc(fence: Fence, device: Device) {
	vk.DestroyFence(device, fence, nil)
}

fence_wait :: proc(fence: ^Fence, device: Device) -> vk.Result {
	return vk.WaitForFences(device, 1, fence, true, max(u64))
}

fence_reset :: proc(fence: ^Fence, device: Device) -> vk.Result {
	return vk.ResetFences(device, 1, fence)
}
