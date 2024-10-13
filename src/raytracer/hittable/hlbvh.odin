package hittable

import "../utils"
import "aabb"
import "core:log"
import "core:sync"
import "core:thread"
_ :: log

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
	start_index, n_primitives: uint,
	build_nodes:               []BVH_Build_Node,
}

hlbvh_build :: proc(
	bvh: BVH,
	primitive_infos: []BVH_Primitive_Info,
	total_nodes: ^uint,
	ordered_prims: ^[dynamic]Hittable,
	allocator := context.allocator,
	temp_allocator := context.temp_allocator,
) -> ^BVH_Build_Node {
	context.allocator = allocator
	context.temp_allocator = temp_allocator
	bounds := calculate_scene_bounds(primitive_infos)
	morton_codes := calculate_morton_codes(primitive_infos, bounds)
	treelets := calculate_treelets(morton_codes)
	total_nodes^ = build_treelets(bvh, treelets, ordered_prims, primitive_infos, morton_codes)
	log.debugf("Total nodes = %d, number of primitives = %d", total_nodes^, len(bvh.primitives))
	finished_treelets := make([dynamic]BVH_Build_Node, 0, len(treelets))
	for &tr in treelets {
		append(&finished_treelets, tr.build_nodes[0])
	}
	return build_upper_sah(bvh, finished_treelets[:], 0, len(finished_treelets), total_nodes)
}

@(private)
build_upper_sah :: proc(
	bvh: BVH,
	treeroots: []BVH_Build_Node,
	start, end: uint,
	total_nodes: ^uint,
) -> ^BVH_Build_Node {
	offset := end - start
	if offset == 1 {
		return &treeroots[start]
	}

	total_nodes^ += 1

	node := new(BVH_Build_Node)

	centroid_bounds := aabb.empty()
	bounds := aabb.empty()
	for &tr in treeroots[start:end] {
		bounds = aabb.merge(bounds, tr.bounds)
		centroid := aabb.centroid(tr.bounds)
		centroid_bounds = aabb.merge(centroid_bounds, centroid)
	}

	dim := aabb.maximum_extent(centroid_bounds)
	buckets: [N_BUCKETS]Bucket_Info
	for i in start ..< end {
		centroid := aabb.centroid(treeroots[i].bounds)
		b := int(N_BUCKETS * aabb.offset(centroid_bounds, centroid)[dim])
		if b == N_BUCKETS do b -= 1

		buckets[b].count += 1
		buckets[b].bounds = aabb.merge(buckets[b].bounds, treeroots[i].bounds)
	}

	cost: [N_BUCKETS - 1]f64
	for i in 0 ..< N_BUCKETS - 1 {
		b0, b1 := aabb.empty(), aabb.empty()
		count0, count1: int
		for j in 0 ..= i {
			b0 = aabb.merge(b0, buckets[j].bounds)
			count0 += buckets[j].count
		}

		for j in (i + 1) ..< N_BUCKETS {
			b1 = aabb.merge(b1, buckets[j].bounds)
			count1 += buckets[j].count
		}

		cost[i] =
			0.125 +
			(f64(count0) * aabb.surface_area(b0) + f64(count1) * aabb.surface_area(b1)) /
				aabb.surface_area(bounds)
	}

	min_cost := cost[0]
	min_cost_split_bucket: uint = 0
	for i in 1 ..< N_BUCKETS - 1 {
		if cost[i] < min_cost {
			min_cost = cost[i]
			min_cost_split_bucket = uint(i)
		}
	}

	mid :=
		start + split_primitives(treeroots[start:end], centroid_bounds, dim, min_cost_split_bucket)
	init_interior(
		node,
		dim,
		build_upper_sah(bvh, treeroots, start, mid, total_nodes),
		build_upper_sah(bvh, treeroots, mid, end, total_nodes),
	)


	return node
}

@(private)
build_treelets :: proc(
	bvh: BVH,
	treelets: []LBVHTreelets,
	ordered_primitives: ^[dynamic]Hittable,
	primitive_info: []BVH_Primitive_Info,
	morton_prims: []Morton_Code,
	allocator := context.allocator,
) -> uint {
	resize(ordered_primitives, len(primitive_info))
	total_nodes: uint = 0
	ordered_prims_offset: uint = 0
	for &tr in treelets {
		root_node: ^BVH_Build_Node
		nodes_created: uint
		first_bit_index: uint = 29 - 12
		log.debug(tr.start_index, tr.n_primitives)
		root_node, nodes_created = emit_lbvh(
			bvh,
			build_nodes = tr.build_nodes,
			primitive_info = primitive_info,
			morton_prims = morton_prims[tr.start_index:],
			n_primitives = tr.n_primitives,
			ordered_prims = ordered_primitives^[:],
			ordered_prims_offset = &ordered_prims_offset,
			bit_index = int(first_bit_index),
		)

		tr.build_nodes[0] = root_node^

		total_nodes += nodes_created
	}
	return total_nodes
}

emit_lbvh :: proc(
	bvh: BVH,
	build_nodes: []BVH_Build_Node,
	primitive_info: []BVH_Primitive_Info,
	morton_prims: []Morton_Code,
	n_primitives: uint,
	ordered_prims: []Hittable,
	ordered_prims_offset: ^uint,
	bit_index: int,
) -> (
	^BVH_Build_Node,
	uint,
) {
	assert(n_primitives > 0)
	if bit_index == -1 || n_primitives < bvh.max_prims_in_node {
		node := &build_nodes[0]
		bounds := aabb.empty()
		first_prim_offset := sync.atomic_add(ordered_prims_offset, n_primitives)

		for i in 0 ..< n_primitives {
			primitive_index := morton_prims[i].primitive_index
			ordered_prims[first_prim_offset + i] = bvh.primitives[primitive_index]
			bounds = aabb.merge(bounds, primitive_info[primitive_index].bounds)
		}
		init_leaf(node, first_prim_offset, n_primitives, bounds)
		// log.debug(node)
		return node, 1
	} else {
		mask: uint = 1 << uint(bit_index)

		if (morton_prims[0].code & mask) == (morton_prims[n_primitives - 1].code & mask) {
			return emit_lbvh(
				bvh,
				build_nodes,
				primitive_info,
				morton_prims,
				n_primitives,
				ordered_prims,
				ordered_prims_offset,
				bit_index - 1,
			)
		}

		search_start: uint
		search_end := n_primitives - 1

		for search_start + 1 < search_end {
			mid := (search_start + search_end) / 2
			if (morton_prims[search_start].code & mask) == (morton_prims[mid].code & mask) {
				search_start = mid
			} else {
				assert((morton_prims[mid].code & mask) == (morton_prims[search_end].code & mask))
				search_end = mid
			}
		}
		split_offset := search_end

		assert(split_offset <= n_primitives - 1)
		assert(
			morton_prims[split_offset - 1].code & mask != morton_prims[split_offset].code & mask,
		)

		node := &build_nodes[0]

		left_nodes, number_left_nodes := emit_lbvh(
			bvh,
			build_nodes[1:],
			primitive_info,
			morton_prims,
			split_offset,
			ordered_prims,
			ordered_prims_offset,
			bit_index - 1,
		)
		right_nodes, number_right_nodes := emit_lbvh(
			bvh,
			build_nodes[(1 + number_left_nodes):],
			primitive_info,
			morton_prims[split_offset:],
			n_primitives - split_offset,
			ordered_prims,
			ordered_prims_offset,
			bit_index - 1,
		)

		// log.debugf("Number of left nodes = %d, left node = %v, right_nodes = %v, number of right nodes = %d", number_left_nodes, left_nodes, right_nodes, number_right_nodes)

		axis := bit_index % 3
		init_interior(node, uint(axis), left_nodes, right_nodes)
		return node, 1 + number_left_nodes + number_right_nodes
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
	start: uint = 0
	for end: uint = 1; end <= len(codes); end += 1 {
		if (end == len(codes) || (codes[start].code & mask != codes[end].code & mask)) {
			n_primitives := end - start
			nodes := make([]BVH_Build_Node, 2 * n_primitives - 1, allocator)
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
