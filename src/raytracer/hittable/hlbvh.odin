package hittable

import "../utils"
import "aabb"
import "core:fmt"
import "core:log"
import "core:thread"

NUM_THREADS :: 16
MORTON_BITS :: 10
MORTON_SCALE :: 1 << MORTON_BITS

Morton_Code :: struct {
	primitive_index: int,
	code:            u32,
}

HLBVH :: struct {
	using bvh: BVH,
}

LBVHTreelets :: struct {
	start_index, n_primitives: int,
	bvh:                       BVH,
}

@(private)
Calculate_Morton_Task :: struct {
	object:       ^Hittable,
	index:        int,
	code:         ^Morton_Code,
	scene_bounds: ^aabb.AABB,
}

hlbvh_init :: proc(
	hlbvh: ^HLBVH,
	objects: []Hittable,
	allocator := context.allocator,
	temp_allocator := context.temp_allocator,
) {
	context.allocator = allocator
	context.temp_allocator = temp_allocator

	scene_bounds := calculate_scene_bounds(objects)

	morton_codes := calculate_morton_codes(objects, scene_bounds)

	treelets := calculate_treelets(morton_codes)
	return
}

@(private)
@(require_results)
calculate_treelets :: proc(
	codes: []Morton_Code,
	allocator := context.allocator,
) -> []LBVHTreelets {
	context.allocator = allocator

	treelets := make([]LBVHTreelets, 0, len(codes))

	mask := 0b00111111111111000000000000000000
	start := 0
	for end := 1; end <= len(codes); end += 1 {
		if (end == len(codes) || (codes[start].code & mask != codes[end].code & mask)) {
			n_primitives := end - start
			append(&treelets, LBVHTreelets{start_index = start, n_primitives = n_primitives})
		}
	}

	return treelets
}

@(private)
@(require_results)
calculate_morton_codes :: proc(
	objects: []Hittable,
	scene_bounds: aabb.AABB,
	allocator := context.allocator,
	temp_allocator := context.temp_allocator,
) -> []Morton_Code {
	context.allocator = allocator
	context.temp_allocator = temp_allocator

	scene_bounds := scene_bounds

	morton_codes := make([]Morton_Code, len(objects))

	pool: thread.Pool
	thread.pool_init(&pool, allocator = context.temp_allocator, thread_count = NUM_THREADS)
	defer thread.pool_destroy(&pool)

	tasks := make([]Calculate_Morton_Task, len(objects), allocator = context.temp_allocator)
	defer delete(tasks)

	for _, i in objects {
		tasks[i] = Calculate_Morton_Task {
			object       = &objects[i],
			index        = i,
			code         = &morton_codes[i],
			scene_bounds = &scene_bounds,
		}
		thread.pool_add_task(&pool, context.allocator, calculate_obj_morton_code_task, &tasks[i])
	}

	thread.pool_start(&pool)
	thread.pool_finish(&pool)

	sort_morton_codes(morton_codes)

	return morton_codes
}

@(private)
@(require_results)
calculate_scene_bounds :: proc(objects: []Hittable) -> aabb.AABB {
	scene_bounds := aabb.empty()
	for &obj in objects {
		scene_bounds = aabb.merge(scene_bounds, hittable_aabb(obj))
	}
	return scene_bounds
}

@(private)
sort_morton_codes :: proc(arr: []Morton_Code, temp_allocator := context.temp_allocator) {
	bits_per_pass: u32 : 6
	n_bits: u32 : 30
	n_passes: u32 : n_bits / bits_per_pass

	temp := make([]Morton_Code, len(arr), temp_allocator)
	defer delete(temp)

	for pass in 0 ..< n_passes {
		low_bit := pass * bits_per_pass
		v_in := (pass & 1 != 0) ? temp[:] : arr[:]
		v_out := (pass & 1 != 0) ? arr[:] : temp[:]

		n_buckets :: 1 << bits_per_pass
		bucket_count: [n_buckets]int
		bit_mask :: (1 << bits_per_pass) - 1

		for &mp in v_in {
			bucket := (mp.code >> low_bit) & bit_mask
			bucket_count[bucket] += 1
		}

		out_index: [n_buckets]int
		out_index[0] = 0
		for i in 1 ..< n_buckets {
			out_index[i] = out_index[i - 1] + bucket_count[i - 1]
		}

		for mp in v_in {
			bucket := (mp.code >> low_bit) & bit_mask
			v_out[out_index[bucket]] = mp
			out_index[bucket] += 1
		}
	}

	if n_passes & 1 != 0 {
		copy(arr, temp)
	}
}

@(private)
calculate_obj_morton_code_task :: proc(task: thread.Task) {
	task_data := cast(^Calculate_Morton_Task)task.data

	centroid_offset := aabb.offset(
		task_data.scene_bounds^,
		aabb.centroid(hittable_aabb(task_data.object^)),
	)
	task_data.code.primitive_index = task_data.index
	task_data.code.code = encode_morton_3(centroid_offset * MORTON_SCALE)
}

@(private)
@(require_results)
encode_morton_3 :: proc(v: utils.Vec3) -> u32 {
	return left_shift_3(u32(v.z)) << 2 | left_shift_3(u32(v.y)) << 1 | left_shift_3(u32(v.x))
}

left_shift_3 :: proc(x: u32) -> u32 {
	x := x
	if x == (1 << 10) do x -= 1
	x = (x | (x << 16)) & 0b00000011000000000000000011111111
	x = (x | (x << 8)) & 0b00000011000000001111000000001111
	x = (x | (x << 4)) & 0b00000011000011000011000011000011
	x = (x | (x << 2)) & 0b00001001001001001001001001001001
	return x
}
