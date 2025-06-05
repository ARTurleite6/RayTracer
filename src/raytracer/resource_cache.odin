package raytracer

import "core:hash/xxhash"
import "core:mem"

import vk "vendor:vulkan"

Resource_Cache :: struct {
	descriptor_set_layots: map[u32]Descriptor_Set_Layout,
	pipeline_layouts:      map[u32]vk.PipelineLayout,
	raytracing_pipelines:  map[u32]vk.Pipeline,
	shaders:               map[u32]Shader,
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
		xxhash.XXH32_update(hasher, mem.any_to_bytes(layout))
		xxhash.XXH32_update(hasher, mem.any_to_bytes(set))
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

vulkan_get_shader :: proc(ctx: ^Vulkan_Context, path: string) -> Shader {
	cache := &ctx.cache

	hash := xxhash.XXH32(transmute([]u8)path)

	if value, found := cache.shaders[hash]; found {
		return value
	}

	shader: Shader
	shader_init(&shader, vulkan_get_device_handle(ctx), path)

	cache.shaders[hash] = shader
	return cache.shaders[hash]
}
