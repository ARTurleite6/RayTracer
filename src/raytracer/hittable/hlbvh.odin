package hittable

import "../utils"
import "aabb"
import "core:sync"
import "core:thread"

NUM_THREADS :: 16
MORTON_BITS :: 10
MORTON_SCALE :: 1 << MORTON_BITS

Morton_Code :: struct {
	primitive_index: int,
	code:            uint,
}

Calculate_Morton_Codes_Task :: struct {
	primitive_info: ^BVH_Primitive_Info,
	morton_prims:   ^Morton_Code,
	bounds:         aabb.AABB,
}

Calculate_Treelet_Task :: struct {
	treelet:                                         ^LBVHTreelets,
	primitive_info:                                  []BVH_Primitive_Info,
	n_primitives:                                    int,
	ordered_prims:                                   []Hittable,
	atomic_ordered_prims_offset, atomic_total_count: ^int,
	bit_index:                                       int,
}

HLBVH :: struct {
	using bvh: BVH,
}

LBVHTreelets :: struct {
	start_index, n_primitives: int,
	build_nodes:               [dynamic]BVH_Build_Node,
}

hlbvh_build :: proc(
	bvh: BVH,
	primitive_infos: []BVH_Primitive_Info,
	total_nodes: ^int,
	ordered_prims: [dynamic]Hittable,
	allocator := context.allocator,
	temp_allocator := context.temp_allocator,
) -> ^BVH_Build_Node {
	context.allocator = allocator
	context.temp_allocator = temp_allocator
	bounds := calculate_scene_bounds(primitive_infos)
	morton_codes := calculate_morton_codes(primitive_infos, bounds)
	treelets := calculate_treelets(morton_codes)
	return {}
}

@(private)
build_treelets :: proc(
	treelets: []LBVHTreelets,
	primitive_info: []BVH_Primitive_Info,
	temp_allocator := context.temp_allocator,
) {

	for &tr in treelets {
		// emit_lbvh()
		_ = tr
	}
}

emit_lbvh :: proc(
	bvh: BVH,
	build_nodes: ^[^]BVH_Build_Node,
	primitive_info: []BVH_Primitive_Info,
	morton_prims: []Morton_Code,
	n_primitives: uint,
	total_nodes: ^uint,
	ordered_prims: ^[dynamic]Hittable,
	ordered_prims_offset: ^uint,
	bit_index: uint,
) -> ^BVH_Build_Node {
	if bit_index == 1 || n_primitives < bvh.max_prims_in_node {
		total_nodes^ += 1
		node := &build_nodes[0]
		build_nodes^ = build_nodes[1:]
		bounds := aabb.empty()
		first_prim_offset := sync.atomic_add(ordered_prims_offset, 1)

		for i in 0 ..< n_primitives {
			primitive_index := morton_prims[i].primitive_index
			ordered_prims[first_prim_offset + 1] = bvh.primitives[primitive_index]
			bounds = aabb.merge(bounds, primitive_info[primitive_index].bounds)
		}
		init_leaf(node, first_prim_offset, n_primitives, bounds)
		return node
	} else {
		mask: uint = 1 << bit_index

		if (morton_prims[0].code & mask) == (morton_prims[n_primitives - 1].code & mask) {
			return emit_lbvh(
				bvh,
				build_nodes,
				primitive_info,
				morton_prims,
				n_primitives,
				total_nodes,
				ordered_prims,
				ordered_prims_offset,
				bit_index - 1,
			)
		}

		search_start: uint
		search_end := n_primitives - 1

		for search_start + 1 != search_end {
			mid := (search_start + search_end) / 2
			if (morton_prims[search_start].code & mask) == (morton_prims[search_end].code & mask) {
				search_start = mid
			} else {
				search_end = mid
			}
		}
		split_offset := search_end

		total_nodes^ += 1
		node := &build_nodes[0]
		build_nodes^ = build_nodes[1:]

		lbvh := [2]^BVH_Build_Node {
			emit_lbvh(
				bvh,
				build_nodes,
				primitive_info,
				morton_prims,
				split_offset,
				total_nodes,
				ordered_prims,
				ordered_prims_offset,
				bit_index - 1,
			),
			emit_lbvh(
				bvh,
				build_nodes,
				primitive_info,
				morton_prims[split_offset:],
				n_primitives - split_offset,
				total_nodes,
				ordered_prims,
				ordered_prims_offset,
				bit_index - 1,
			),
		}

		axis := bit_index % 3
		init_interior(node, axis, lbvh[0], lbvh[1])
		return node
	}
}

@(private)
@(require_results)
calculate_treelets :: proc(
	codes: []Morton_Code,
	allocator := context.allocator,
) -> []LBVHTreelets {
	context.allocator = allocator

	treelets := make([dynamic]LBVHTreelets, 0, len(codes))

	mask: uint = 0b00111111111111000000000000000000
	start := 0
	for end := 1; end <= len(codes); end += 1 {
		if (end == len(codes) || (codes[start].code & mask != codes[end].code & mask)) {
			n_primitives := end - start
			nodes := make([dynamic]BVH_Build_Node, 0, 2 * n_primitives - 1, allocator)
			append(
				&treelets,
				LBVHTreelets {
					start_index = start,
					n_primitives = n_primitives,
					build_nodes = nodes,
				},
			)
			start = end
		}
	}

	return treelets[:]
}

@(private)
@(require_results)
calculate_morton_codes :: proc(
	objects: []BVH_Primitive_Info,
	scene_bounds: aabb.AABB,
	allocator := context.allocator,
	temp_allocator := context.temp_allocator,
) -> []Morton_Code {
	context.allocator = allocator
	context.temp_allocator = temp_allocator

	morton_codes := make([]Morton_Code, len(objects))

	pool: thread.Pool
	thread.pool_init(&pool, allocator = context.temp_allocator, thread_count = NUM_THREADS)
	defer thread.pool_destroy(&pool)

	tasks := make([]Calculate_Morton_Codes_Task, len(objects), context.temp_allocator)
	defer delete(tasks)

	for _, i in objects {
		tasks[i] = Calculate_Morton_Codes_Task {
			morton_prims   = &morton_codes[i],
			primitive_info = &objects[i],
			bounds         = scene_bounds,
		}
		thread.pool_add_task(&pool, context.allocator, calculate_obj_morton_code_task, &tasks[i])
	}

	thread.pool_start(&pool)
	thread.pool_finish(&pool)

	sort_morton_codes(morton_codes)

	return morton_codes
}

@(private)
sort_morton_codes :: proc(arr: []Morton_Code, temp_allocator := context.temp_allocator) {
	bits_per_pass: uint : 6
	n_bits: uint : 30
	n_passes: uint : n_bits / bits_per_pass

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
	task_info := cast(^Calculate_Morton_Codes_Task)task.data
	morton_prims := task_info.morton_prims
	primitive_info := task_info.primitive_info
	bounds := task_info.bounds

	morton_prims.primitive_index = primitive_info.primitive_number
	centroid_offset := aabb.offset(bounds, primitive_info.centroid)
	morton_prims.code = encode_morton_3(centroid_offset * MORTON_SCALE)
}

@(private)
@(require_results)
encode_morton_3 :: proc(v: utils.Vec3) -> uint {
	return left_shift_3(uint(v.z)) << 2 | left_shift_3(uint(v.y)) << 1 | left_shift_3(uint(v.x))
}

left_shift_3 :: proc(x: uint) -> uint {
	x := x
	if x == (1 << 10) do x -= 1
	x = (x | (x << 16)) & 0b00000011000000000000000011111111
	x = (x | (x << 8)) & 0b00000011000000001111000000001111
	x = (x | (x << 4)) & 0b00000011000011000011000011000011
	x = (x | (x << 2)) & 0b00001001001001001001001001001001
	return x
}
