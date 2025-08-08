package raytracer

import "base:runtime"
import "core:log"
import "core:os"
import "core:slice"
import "core:strings"

import spirv "external:odin-spirv-reflect"
import vk "vendor:vulkan"

Shader_Error :: enum {
	None = 0,
	File_Non_Existent,
	Shader_Creation_Error,
}

Resource_Layout :: struct {
	sets:        [dynamic]Descriptor_Set_Layout_Info,
	push_ranges: [dynamic]vk.PushConstantRange,
}

Descriptor_Set_Layout_Info :: struct {
	set:      u32,
	bindings: [dynamic]vk.DescriptorSetLayoutBinding,
}

Shader :: struct {
	name:        string,
	entry_point: string,
	type:        vk.ShaderStageFlags,
	module:      vk.ShaderModule,
	device:      vk.Device,
	code:        []u8,
}

Program :: struct {
	pipeline_layout: vk.PipelineLayout,
	shaders:         []Shader,
}

@(require_results)
make_program :: proc(
	ctx: ^Vulkan_Context,
	shaders: []string,
	allocator := context.allocator,
) -> (
	prog: Program,
) {
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(allocator == context.temp_allocator)
	context.allocator = allocator
	prog.shaders = make([]Shader, len(shaders))
	for shader_path, i in shaders {
		prog.shaders[i] = vulkan_get_shader(ctx, shader_path)
	}

	layouts := make([]Resource_Layout, len(shaders), context.temp_allocator)
	for shader, i in prog.shaders {
		layouts[i] = shader_get_resource_layout(shader, context.temp_allocator)
	}

	merged_layout := merge_resource_layouts(layouts, context.temp_allocator)

	layout_sets := make([]vk.DescriptorSetLayout, len(merged_layout.sets), context.temp_allocator)

	for set_info in merged_layout.sets {
		layout := vulkan_get_descriptor_set_layout(ctx, ..set_info.bindings[:])
		layout_sets[set_info.set] = layout.handle
	}

	prog.pipeline_layout = vulkan_get_pipeline_layout(
		ctx,
		layout_sets[:],
		merged_layout.push_ranges[:],
	)

	return prog
}

program_destroy :: proc(prog: ^Program) {
	delete(prog.shaders)
}

shader_init :: proc(
	shader: ^Shader,
	device: vk.Device,
	path: string,
	allocator := context.allocator,
) -> (
	err: Shader_Error,
) {
	shader.device = device

	data, ok := os.read_entire_file(path, allocator = allocator)
	if !ok {
		return .File_Non_Existent
	}

	shader.code = data

	content := transmute([]u32)data

	spirv_module: spirv.ShaderModule
	result := spirv.CreateShaderModule(len(data), raw_data(data), &spirv_module)
	assert(result == .SUCCESS)
	defer spirv.DestroyShaderModule(&spirv_module)

	shader.name = strings.clone_from_cstring(spirv_module.entry_point_name)
	shader.entry_point = strings.clone_from_cstring(spirv_module.entry_point_name)
	shader.type = spirv_module.shader_stage

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(content),
		pCode    = &content[0],
	}

	if vk_check(
		   vk.CreateShaderModule(device, &create_info, nil, &shader.module),
		   "Failed to create shader module",
	   ) !=
	   .SUCCESS {
		return .Shader_Creation_Error
	}

	return .None
}

shader_get_resource_layout :: proc(
	shader: Shader,
	allocator := context.allocator,
) -> (
	layout: Resource_Layout,
) {
	module: spirv.ShaderModule
	result := spirv.CreateShaderModule(len(shader.code), raw_data(shader.code), &module)
	assert(result == .SUCCESS)
	defer spirv.DestroyShaderModule(&module)

	context.allocator = allocator

	{
		count: u32
		spirv.EnumerateDescriptorSets(module, &count, nil)
		descriptor_sets := make([]^spirv.DescriptorSet, count, context.temp_allocator)
		spirv.EnumerateDescriptorSets(module, &count, raw_data(descriptor_sets))

		for descriptor_set in descriptor_sets {
			set_layout := Descriptor_Set_Layout_Info {
				set = descriptor_set.set,
			}
			set_layout.bindings = make(
				[dynamic]vk.DescriptorSetLayoutBinding,
				0,
				descriptor_set.binding_count,
				allocator,
			)

			for binding in descriptor_set.bindings[:descriptor_set.binding_count] {
				append(
					&set_layout.bindings,
					vk.DescriptorSetLayoutBinding {
						binding = binding.binding,
						descriptorType = binding.descriptor_type,
						descriptorCount = binding.count,
						stageFlags = module.shader_stage,
					},
				)
			}

			append(&layout.sets, set_layout)
		}
	}

	{
		count: u32
		spirv.EnumeratePushConstantBlocks(module, &count, nil)
		push_ranges := make([]^spirv.BlockVariable, count, context.temp_allocator)
		spirv.EnumeratePushConstantBlocks(module, &count, raw_data(push_ranges))

		layout.push_ranges = make([dynamic]vk.PushConstantRange, 0, count, allocator)

		for push_range in push_ranges {
			append(
				&layout.push_ranges,
				vk.PushConstantRange {
					stageFlags = module.shader_stage,
					offset = push_range.offset,
					size = push_range.size,
				},
			)
		}
	}

	return layout
}

// TODO: create function to create shader program,
// that using reflection it creates both the descriptor set layouts and the pipeline layout

shader_destroy :: proc(shader: ^Shader) {
	vk.DestroyShaderModule(shader.device, shader.module, nil)
	shader.module = 0
	delete(shader.name)
	delete(shader.entry_point)
	delete(shader.code)
}

merge_resource_layouts :: proc(
	layouts: []Resource_Layout,
	allocator := context.allocator,
) -> (
	merged_layout: Resource_Layout,
) {
	context.allocator = allocator
	set_map := make(map[u32]Descriptor_Set_Layout_Info, context.temp_allocator)

	for layout in layouts {
		for set_info in layout.sets {
			if existing_set, exists := &set_map[set_info.set]; exists {
				merge_bindings_into_set(existing_set, set_info, allocator)
			} else {
				new_set := Descriptor_Set_Layout_Info {
					set = set_info.set,
				}

				new_set.bindings = make(
					[dynamic]vk.DescriptorSetLayoutBinding,
					0,
					len(set_info.bindings),
					allocator,
				)

				// Copy all bindings from the current set
				for binding in set_info.bindings {
					append(&new_set.bindings, binding)
				}

				set_map[set_info.set] = new_set
			}
		}
	}

	for layout in layouts {
		for push_range in layout.push_ranges {
			append(&merged_layout.push_ranges, push_range)
		}
	}

	for _, set in set_map {
		append(&merged_layout.sets, set)
	}

	slice.sort_by_key(merged_layout.sets[:], proc(layout: Descriptor_Set_Layout_Info) -> u32 {
		return layout.set
	})

	return merged_layout
}

merge_bindings_into_set :: proc(
	target_set: ^Descriptor_Set_Layout_Info,
	source_set: Descriptor_Set_Layout_Info,
	allocator := context.allocator,
) {
	// Create a map of existing bindings by binding number
	binding_map := make(map[u32]int, context.temp_allocator)

	// Map existing bindings
	for binding, i in target_set.bindings {
		binding_map[binding.binding] = i
	}

	// Process source bindings
	for source_binding in source_set.bindings {
		if existing_index, exists := binding_map[source_binding.binding]; exists {
			// Binding already exists, merge stage flags
			target_set.bindings[existing_index].stageFlags |= source_binding.stageFlags

			// Verify that descriptor type and count match
			existing_binding := &target_set.bindings[existing_index]
			if existing_binding.descriptorType != source_binding.descriptorType {
				log.warnf(
					"Warning: Binding %d in set %d has conflicting descriptor types\n",
					source_binding.binding,
					source_set.set,
				)
			}
			if existing_binding.descriptorCount != source_binding.descriptorCount {
				log.warnf(
					"Warning: Binding %d in set %d has conflicting descriptor counts\n",
					source_binding.binding,
					source_set.set,
				)
			}
		} else {
			// New binding, add it
			append(&target_set.bindings, source_binding)
			binding_map[source_binding.binding] = len(target_set.bindings) - 1
		}
	}
}
