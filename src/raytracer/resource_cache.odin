package raytracer

import "core:hash/xxhash"
import "core:mem"

import vk "vendor:vulkan"

Resource_Cache :: struct {
	descriptor_set_layouts: map[u32]^Descriptor_Set_Layout,
	descriptor_pools:       map[u32]^Descriptor_Pool,
	descriptor_sets:        map[u32]Resource_Tracked_Descriptor_Set,
	pipeline_layouts:       map[u32]^Pipeline_Layout,
	raytracing_pipelines:   map[u32]^Raytracing_Pipeline,
	graphics_pipelines:     map[u32]^Graphics_Pipeline,
}

MAX_FRAMES_TTL :: 10

Resource_Tracked_Descriptor_Set :: struct {
	set:     ^Descriptor_Set,
	counter: u64,
}

resource_cache_init :: proc(ctx: ^Vulkan_Context, allocator := context.allocator) {
	context.allocator = allocator
	cache := &ctx.cache

	cache.descriptor_set_layouts = make(map[u32]^Descriptor_Set_Layout)
	cache.pipeline_layouts = make(map[u32]^Pipeline_Layout)
	cache.raytracing_pipelines = make(map[u32]^Raytracing_Pipeline)
}

resource_cache_destroy :: proc(ctx: ^Vulkan_Context, allocator := context.allocator) {
	context.allocator = allocator
	cache := &ctx.cache

	for _, &s in cache.descriptor_sets {
		descriptor_set_destroy(s.set)
		free(s.set)
	}
	delete(cache.descriptor_sets)

	for _, &pool in cache.descriptor_pools {
		descriptor_pool_destroy(pool, ctx)
		free(pool)
	}
	delete(cache.descriptor_pools)

	for _, l in cache.descriptor_set_layouts {
		descriptor_set_layout_destroy(l, ctx)
		free(l)
	}
	delete(cache.descriptor_set_layouts)

	for _, p in cache.raytracing_pipelines {
		raytracing_pipeline_destroy(p, ctx)
		free(p)
	}
	delete(cache.raytracing_pipelines)

	for _, p in cache.graphics_pipelines {
		graphics_pipeline_destroy(p, ctx)
		free(p)
	}
	delete(cache.graphics_pipelines)

	for _, l in cache.pipeline_layouts {
		pipeline_layout_destroy(l, ctx)
		free(l)
	}
	delete(cache.pipeline_layouts)
}

resource_cache_cleanup_unused :: proc(resource_cache: ^Resource_Cache, ctx: ^Vulkan_Context) {
	hashes_to_delete := make(
		[dynamic]u32,
		0,
		len(resource_cache.descriptor_sets),
		context.temp_allocator,
	)
	for hash, &tracked_set in resource_cache.descriptor_sets {
		if tracked_set.counter > MAX_FRAMES_TTL {
			descriptor_set_destroy(tracked_set.set)
			free(tracked_set.set)
			append(&hashes_to_delete, hash)
		} else {
			tracked_set.counter += 1
		}
	}

	for hash in hashes_to_delete {
		delete_key(&resource_cache.descriptor_sets, hash)
	}
}

@(require_results)
resource_cache_request_pipeline_layout :: proc(
	resource_cache: ^Resource_Cache,
	ctx: ^Vulkan_Context,
	shader_modules: []^Shader_Module,
) -> (
	layout: ^Pipeline_Layout,
	err: vk.Result,
) {
	state, _ := xxhash.XXH32_create_state(context.temp_allocator)
	defer xxhash.XXH32_destroy_state(state, context.temp_allocator)
	hash_param(state, shader_modules)
	hash := xxhash.XXH32_digest(state)
	_, value_ptr, just_inserted, _ := map_entry(&resource_cache.pipeline_layouts, hash)
	if just_inserted {
		value_ptr^ = new(Pipeline_Layout)
		pipeline_layout_init2(value_ptr^, ctx, shader_modules) or_return
	}

	return value_ptr^, nil
}

@(require_results)
resource_cache_request_raytracing_pipeline :: proc(
	resource_cache: ^Resource_Cache,
	ctx: ^Vulkan_Context,
	pipeline_state: Pipeline_State,
) -> (
	pipeline: ^Raytracing_Pipeline,
	err: vk.Result,
) {
	state, _ := xxhash.XXH32_create_state(context.temp_allocator)
	defer xxhash.XXH32_destroy_state(state, context.temp_allocator)
	hash_param(state, pipeline_state)
	hash := xxhash.XXH32_digest(state)
	_, value_ptr, just_inserted, _ := map_entry(&resource_cache.raytracing_pipelines, hash)
	if just_inserted {
		value_ptr^ = new(Raytracing_Pipeline)
		raytracing_pipeline_init(value_ptr^, ctx, pipeline_state) or_return
	}

	return value_ptr^, nil
}

@(require_results)
resource_cache_request_graphics_pipeline :: proc(
	resource_cache: ^Resource_Cache,
	ctx: ^Vulkan_Context,
	pipeline_state: Pipeline_State,
) -> (
	pipeline: ^Graphics_Pipeline,
	err: vk.Result,
) {
	state, _ := xxhash.XXH32_create_state(context.temp_allocator)
	defer xxhash.XXH32_destroy_state(state, context.temp_allocator)
	hash_param(state, pipeline_state)
	hash := xxhash.XXH32_digest(state)
	_, value_ptr, just_inserted, _ := map_entry(&resource_cache.graphics_pipelines, hash)
	if just_inserted {
		value_ptr^ = new(Graphics_Pipeline)
		graphics_pipeline_init(value_ptr^, ctx, pipeline_state) or_return
	}

	return value_ptr^, nil
}

@(require_results)
resource_cache_request_descriptor_set_layout2 :: proc(
	resource_cache: ^Resource_Cache,
	ctx: ^Vulkan_Context,
	set_index: u32,
	shaders: []^Shader_Module,
	set_resources: []Shader_Resource,
) -> (
	layout: ^Descriptor_Set_Layout,
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

	if value, ok := resource_cache.descriptor_set_layouts[hash]; ok {
		return value, nil
	}

	layout = new(Descriptor_Set_Layout)
	descriptor_set_layout_init(layout, ctx, set_index, shaders, set_resources) or_return
	resource_cache.descriptor_set_layouts[hash] = layout

	return layout, nil
}

@(require_results)
resource_cache_request_descriptor_pool :: proc(
	resource_cache: ^Resource_Cache,
	ctx: ^Vulkan_Context,
	layout: ^Descriptor_Set_Layout,
) -> (
	pool: ^Descriptor_Pool,
) {
	state, _ := xxhash.XXH32_create_state(context.temp_allocator)
	defer xxhash.XXH32_destroy_state(state, context.temp_allocator)
	hash_param(state, layout^)
	hash_value := xxhash.XXH32_digest(state)

	_, value_ptr, just_inserted, _ := map_entry(&resource_cache.descriptor_pools, hash_value)
	if just_inserted {
		value_ptr^ = new(Descriptor_Pool)
		descriptor_pool2_init(value_ptr^, layout)
	}

	return value_ptr^
}

@(require_results)
resource_cache_request_descriptor_set2 :: proc(
	resource_cache: ^Resource_Cache,
	ctx: ^Vulkan_Context,
	layout: ^Descriptor_Set_Layout,
	buffer_infos: Binding_Map(vk.DescriptorBufferInfo),
	image_infos: Binding_Map(vk.DescriptorImageInfo),
	acceleration_structure_infos: Binding_Map(vk.WriteDescriptorSetAccelerationStructureKHR),
) -> (
	set: ^Descriptor_Set,
	err: vk.Result,
) {
	state, _ := xxhash.XXH32_create_state(context.temp_allocator)
	defer xxhash.XXH32_destroy_state(state, context.temp_allocator)
	hash_param(state, layout^)
	hash_param(state, buffer_infos)
	hash_param(state, image_infos)

	hash_value := xxhash.XXH32_digest(state)
	_, value_ptr, just_inserted, _ := map_entry(&resource_cache.descriptor_sets, hash_value)

	if just_inserted {
		value_ptr.set = new(Descriptor_Set)
		pool := resource_cache_request_descriptor_pool(resource_cache, ctx, layout)
		descriptor_set_init(
			value_ptr.set,
			ctx,
			layout,
			pool,
			buffer_infos,
			image_infos,
			acceleration_structure_infos,
		)
	}

	value_ptr.counter = 0
	return value_ptr.set, nil
}
