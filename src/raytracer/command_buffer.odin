package raytracer

import vk "vendor:vulkan"

Command_Buffer :: struct {
	name:   string,
	handle: vk.CommandBuffer,
}
