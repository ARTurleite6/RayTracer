package raytracer

import vk "vendor:vulkan"

Semaphore :: vk.Semaphore

@(require_results)
semaphore_init :: proc(semaphore: ^Semaphore, device: Device) -> vk.Result {
	create_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	return vk.CreateSemaphore(device, &create_info, nil, semaphore)
}

semaphore_destroy :: proc(semaphore: Semaphore, device: Device) {
	vk.DestroySemaphore(device, semaphore, nil)
}
