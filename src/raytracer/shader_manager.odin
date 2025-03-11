package raytracer

import "core:fmt"
import spirv "external:odin-spirv-reflect"
import vk "vendor:vulkan"
_ :: spirv
_ :: fmt

Shader2 :: struct {
	device: ^Device,
	module: vk.ShaderModule,
}

shader_init2 :: proc(shader: ^Shader2, device: ^Device, data: []u32, size: int) {
	shader.device = device
	{ 	// create shader_module
		create_info := vk.ShaderModuleCreateInfo {
			sType    = .SHADER_MODULE_CREATE_INFO,
			codeSize = size,
			pCode    = &data[0],
		}

		_ = vk_check(
			vk.CreateShaderModule(
				shader.device.logical_device.ptr,
				&create_info,
				nil,
				&shader.module,
			),
			"Failed to create shader",
		)
	}
	resource_layout(raw_data(data), uint(size))
}

@(private = "file")
resource_layout :: proc(data: rawptr, size: uint) {
	module: spirv.ShaderModule
	spirv.CreateShaderModule(size, data, &module)
	defer spirv.DestroyShaderModule(&module)

	count: u32
	spirv.EnumeratePushConstantBlocks(module, &count, nil)
	block := make([]^spirv.BlockVariable, count, context.temp_allocator)
	spirv.EnumeratePushConstantBlocks(module, &count, raw_data(block))

	for b in block {
		fmt.println(b.name)
	}

	// for b in block {
	// 	fmt.println(b.name)
	// }
	// TODO: perform reflection on shaders
}
