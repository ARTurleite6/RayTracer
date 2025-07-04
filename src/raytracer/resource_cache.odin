package raytracer

import "core:hash/xxhash"
import "core:log"
import "core:mem"

import vk "vendor:vulkan"

Resource_Cache :: struct {
	descriptor_set_layouts2: map[u32]^Descriptor_Set_Layout2,
	descriptor_set_layots:   map[u32]Descriptor_Set_Layout,
	pipeline_layouts:        map[u32]vk.PipelineLayout,
	descriptor_sets:         map[u32]vk.DescriptorSet,
	raytracing_pipelines:    map[u32]vk.Pipeline,
	shaders:                 map[u32]Shader,
}

resource_cache_init :: proc(ctx: ^Vulkan_Context, allocator := context.allocator) {
	context.allocator = allocator
	cache := &ctx.cache

	cache.descriptor_set_layots = make(map[u32]Descriptor_Set_Layout)
	cache.pipeline_layouts = make(map[u32]vk.PipelineLayout)
	cache.raytracing_pipelines = make(map[u32]vk.Pipeline)
	cache.shaders = make(map[u32]Shader)
}

resource_cache_destroy :: proc(ctx: ^Vulkan_Context, allocator := context.allocator) {
	context.allocator = allocator
	cache := &ctx.cache

	delete(cache.descriptor_set_layots)
	delete(cache.pipeline_layouts)
	delete(cache.raytracing_pipelines)

	for _, &shader in cache.shaders {
		shader_destroy(&shader)
	}
	delete(cache.shaders)
}

resource_cache_request_descriptor_set_layout :: proc(
	resource_cache: ^Resource_Cache,
	ctx: ^Vulkan_Context,
	set_index: u32,
	shaders: []^Shader_Module,
	set_resources: []Shader_Resource,
) -> (
	layout: ^Descriptor_Set_Layout2,
	err: vk.Result,
) {
	hasher, _ := xxhash.XXH32_create_state(context.temp_allocator)
	defer xxhash.XXH32_destroy_state(hasher, context.temp_allocator)

	for &resource in set_resources {
		if resource.type == .Input ||
		   resource.type == .Output ||
		   resource.type == .Push_Constant ||
		   resource.type == .Specialization_Constant {
			continue
		}

		xxhash.XXH32_update(hasher, mem.any_to_bytes(resource.set))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(resource.binding))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(resource.type))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(resource.mode))
	}

	for shader in shaders {
		xxhash.XXH32_update(hasher, mem.any_to_bytes(shader.id))
	}

	xxhash.XXH32_update(hasher, mem.any_to_bytes(set_index))

	hash := xxhash.XXH32_digest(hasher)

	if value, ok := resource_cache.descriptor_set_layouts2[hash]; ok {
		return value, nil
	}

	layout = new(Descriptor_Set_Layout2)
	descriptor_set_layout2_init(layout, ctx, set_index, shaders, set_resources) or_return
	resource_cache.descriptor_set_layouts2[hash] = layout

	return layout, nil
}

vulkan_get_descriptor_set_layout :: proc(
	ctx: ^Vulkan_Context,
	bindings: ..vk.DescriptorSetLayoutBinding,
) -> Descriptor_Set_Layout {
	cache := &ctx.cache

	context.allocator = context.temp_allocator
	hasher, _ := xxhash.XXH32_create_state()
	defer xxhash.XXH32_destroy_state(hasher)

	for &binding in bindings {
		xxhash.XXH32_update(hasher, mem.any_to_bytes(binding.binding))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(binding.descriptorType))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(binding.descriptorCount))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(binding.stageFlags))
	}

	value := xxhash.XXH32_digest(hasher)

	if value, found := cache.descriptor_set_layots[value]; found {
		return value
	}

	cache.descriptor_set_layots[value] = create_descriptor_set_layout(ctx, ..bindings)

	return cache.descriptor_set_layots[value]
}

vulkan_get_descriptor_set :: proc(
	ctx: ^Vulkan_Context,
	descriptor_set_layout: ^Descriptor_Set_Layout,
	write_infos: ..Descriptor_Set_Write_Info,
) -> vk.DescriptorSet {
	cache := &ctx.cache
	context.allocator = context.temp_allocator
	hasher, _ := xxhash.XXH32_create_state()
	defer xxhash.XXH32_destroy_state(hasher)

	xxhash.XXH32_update(hasher, mem.any_to_bytes(descriptor_set_layout))

	for w in write_infos {
		xxhash.XXH32_update(hasher, mem.any_to_bytes(w.binding))

		switch v in w.write_info {
		case vk.DescriptorBufferInfo:
			xxhash.XXH32_update(hasher, mem.any_to_bytes(v.buffer))
			xxhash.XXH32_update(hasher, mem.any_to_bytes(v.offset))
			xxhash.XXH32_update(hasher, mem.any_to_bytes(v.range))
		case vk.DescriptorImageInfo:
			xxhash.XXH32_update(hasher, mem.any_to_bytes(v.sampler))
			xxhash.XXH32_update(hasher, mem.any_to_bytes(v.imageView))
			xxhash.XXH32_update(hasher, mem.any_to_bytes(v.imageLayout))
		case vk.WriteDescriptorSetAccelerationStructureKHR:
			xxhash.XXH32_update(hasher, mem.any_to_bytes(v.accelerationStructureCount))

			for a in v.pAccelerationStructures[:v.accelerationStructureCount] {
				xxhash.XXH32_update(hasher, mem.any_to_bytes(a))
			}
		}
	}

	value := xxhash.XXH32_digest(hasher)
	if value, found := cache.descriptor_sets[value]; found {
		return value
	}

	cache.descriptor_sets[value] = descriptor_set_allocate(descriptor_set_layout)
	log.info("Allocating new descriptor set, with write_infos %v", write_infos)

	descriptor_set_update(cache.descriptor_sets[value], ctx, descriptor_set_layout^, ..write_infos)

	return cache.descriptor_sets[value]
}

vulkan_get_pipeline_layout :: proc(
	ctx: ^Vulkan_Context,
	descriptor_set_layouts: []vk.DescriptorSetLayout,
	push_constant_ranges: []vk.PushConstantRange,
) -> vk.PipelineLayout {
	cache := &ctx.cache
	context.allocator = context.temp_allocator
	hasher, _ := xxhash.XXH32_create_state()
	defer xxhash.XXH32_destroy_state(hasher)

	for layout, set in descriptor_set_layouts {
		xxhash.XXH32_update(hasher, mem.any_to_bytes(set))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(layout))
	}

	for range in push_constant_ranges {
		xxhash.XXH32_update(hasher, mem.any_to_bytes(range))
	}

	value := xxhash.XXH32_digest(hasher)

	if value, found := cache.pipeline_layouts[value]; found {
		return value
	}

	cache.pipeline_layouts[value] = pipeline_layout_init(
		ctx,
		descriptor_set_layouts,
		push_constant_ranges,
	)

	return cache.pipeline_layouts[value]
}

vulkan_get_raytracing_pipeline :: proc(
	ctx: ^Vulkan_Context,
	shaders: []vk.PipelineShaderStageCreateInfo,
	groups: []vk.RayTracingShaderGroupCreateInfoKHR,
	max_pipeline_recursion: u32,
	layout: vk.PipelineLayout,
) -> vk.Pipeline {
	cache := &ctx.cache
	context.allocator = context.temp_allocator
	hasher, _ := xxhash.XXH32_create_state()
	defer xxhash.XXH32_destroy_state(hasher)

	for shader in shaders {
		xxhash.XXH32_update(hasher, mem.any_to_bytes(shader.flags))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(shader.stage))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(shader.module))
	}

	for group in groups {
		xxhash.XXH32_update(hasher, mem.any_to_bytes(group.type))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(group.generalShader))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(group.closestHitShader))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(group.anyHitShader))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(group.intersectionShader))
	}

	xxhash.XXH32_update(hasher, mem.any_to_bytes(max_pipeline_recursion))
	xxhash.XXH32_update(hasher, mem.any_to_bytes(layout))

	value := xxhash.XXH32_digest(hasher)

	if value, found := cache.raytracing_pipelines[value]; found {
		return value
	}

	create_info := vk.RayTracingPipelineCreateInfoKHR {
		sType                        = .RAY_TRACING_PIPELINE_CREATE_INFO_KHR,
		stageCount                   = u32(len(shaders)),
		pStages                      = raw_data(shaders),
		groupCount                   = u32(len(groups)),
		pGroups                      = raw_data(groups),
		maxPipelineRayRecursionDepth = max_pipeline_recursion,
		layout                       = layout,
	}

	pipeline: vk.Pipeline
	vk.CreateRayTracingPipelinesKHR(
		vulkan_get_device_handle(ctx),
		0,
		0,
		1,
		&create_info,
		nil,
		&pipeline,
	)


	cache.raytracing_pipelines[value] = pipeline
	return cache.raytracing_pipelines[value]
}

vulkan_get_shader :: proc(
	ctx: ^Vulkan_Context,
	path: string,
	allocator := context.allocator,
) -> Shader {
	cache := &ctx.cache

	hash := xxhash.XXH32(transmute([]u8)path)

	if value, found := cache.shaders[hash]; found {
		return value
	}

	shader: Shader
	shader_init(&shader, vulkan_get_device_handle(ctx), path, allocator)

	cache.shaders[hash] = shader
	return cache.shaders[hash]
}
