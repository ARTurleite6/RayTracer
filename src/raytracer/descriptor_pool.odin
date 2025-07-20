package raytracer

import vk "vendor:vulkan"

MAX_SETS_PER_POOL: u32 : 16

Descriptor_Pool :: struct {
	pool_max_sets:         u32,
	pools:                 [dynamic]vk.DescriptorPool,
	pool_set_counts:       [dynamic]u32,
	pool_index:            u32,
	pool_sizes:            [dynamic]vk.DescriptorPoolSize,
	set_pool_mapping:      map[vk.DescriptorSet]u32,
	descriptor_set_layout: ^Descriptor_Set_Layout2,
}

descriptor_pool2_init :: proc(
	pool: ^Descriptor_Pool,
	descriptor_set_layout: ^Descriptor_Set_Layout2,
	pool_size := MAX_SETS_PER_POOL,
) {
	pool^ = {}
	pool.descriptor_set_layout = descriptor_set_layout
	pool.pool_max_sets = pool_size
	bindings := &pool.descriptor_set_layout.bindings

	descriptor_type_counts := make(map[vk.DescriptorType]u32)
	defer delete(descriptor_type_counts)

	for binding in bindings {
		descriptor_type_counts[binding.descriptorType] += binding.descriptorCount
	}

	pool.pool_sizes = make([dynamic]vk.DescriptorPoolSize, 0, len(descriptor_type_counts))

	for type, count in descriptor_type_counts {
		pool_size := vk.DescriptorPoolSize {
			type            = type,
			descriptorCount = count * pool_size,
		}

		append(&pool.pool_sizes, pool_size)
	}
}

descriptor_pool_destroy :: proc(pool: ^Descriptor_Pool, ctx: ^Vulkan_Context) {
	for p in pool.pools {
		vk.DestroyDescriptorPool(vulkan_get_device_handle(ctx), p, nil)
	}
	delete(pool.pools)
	delete(pool.pool_set_counts)
	delete(pool.pool_sizes)
	delete(pool.set_pool_mapping)
}

descriptor_pool_reset :: proc(pool: ^Descriptor_Pool, ctx: ^Vulkan_Context) {
	for p in pool.pools {
		vk.ResetDescriptorPool(vulkan_get_device_handle(ctx), p, {})
	}

	for &set_count in pool.pool_set_counts {
		set_count = 0
	}
	clear(&pool.set_pool_mapping)
	pool.pool_index = 0
}

descriptor_pool_allocate :: proc(
	pool: ^Descriptor_Pool,
	ctx: ^Vulkan_Context,
) -> (
	handle: vk.DescriptorSet,
	err: vk.Result,
) {
	pool_index := find_available_pool(pool, ctx, pool.pool_index) or_return

	set_layout := pool.descriptor_set_layout.handle

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = pool.pools[pool_index],
		descriptorSetCount = 1,
		pSetLayouts        = &set_layout,
	}

	vk.AllocateDescriptorSets(vulkan_get_device_handle(ctx), &alloc_info, &handle) or_return
	pool.pool_set_counts[pool_index] += 1
	pool.set_pool_mapping[handle] = pool_index
	return handle, nil
}

@(private = "file")
find_available_pool :: proc(
	pool: ^Descriptor_Pool,
	ctx: ^Vulkan_Context,
	search_index: u32,
) -> (
	value: u32,
	result: vk.Result,
) {
	if u32(len(pool.pools)) <= search_index {

		create_info := vk.DescriptorPoolCreateInfo {
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			poolSizeCount = u32(len(pool.pool_sizes)),
			pPoolSizes    = raw_data(pool.pool_sizes),
			maxSets       = pool.pool_max_sets,
			flags         = {},
		}

		binding_flags := &pool.descriptor_set_layout.binding_flags
		for b in binding_flags {
			if .UPDATE_AFTER_BIND_EXT in b {
				create_info.flags += {.UPDATE_AFTER_BIND_EXT}
			}
		}

		handle: vk.DescriptorPool
		vk.CreateDescriptorPool(
			vulkan_get_device_handle(ctx),
			&create_info,
			nil,
			&handle,
		) or_return

		append(&pool.pools, handle)

		append(&pool.pool_set_counts, 0)

		return search_index, nil
	} else if pool.pool_set_counts[search_index] < pool.pool_max_sets {
		return search_index, nil
	}

	return find_available_pool(pool, ctx, search_index + 1)
}
