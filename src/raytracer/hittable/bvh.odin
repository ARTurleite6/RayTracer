package hittable

import "../interval"
import "../ray"
import "../utils"
import "aabb"
import "core:container/queue"
import "core:log"
import "core:slice"

_ :: log

N_BUCKETS :: 12

Bucket_Info :: struct {
	count:  int,
	bounds: aabb.AABB,
}

BVH :: struct {
	max_prims_in_node: uint,
	split_method:      Split_Method,
	primitives:        []Hittable,
	nodes:             []Linear_BVH_Node,
}

Linear_BVH_Node :: struct {
	bounds:       aabb.AABB,
	offset:       uint, // either primitive offset, either second child offset
	n_primitives: u16,
	axis:         u8,
}

Split_Method :: enum {
	SAH,
	HLBVH,
}

BVH_Primitive_Info :: struct {
	primitive_number: int,
	bounds:           aabb.AABB,
	centroid:         utils.Vec3,
}

BVH_Build_Node :: struct {
	bounds:                                      aabb.AABB,
	children:                                    [2]^BVH_Build_Node,
	split_axis, first_prim_offset, n_primitives: uint,
}

bvh_init :: proc(
	bvh: ^BVH,
	primitives: []Hittable,
	max_prims_in_node: uint,
	split_method: Split_Method,
	allocator := context.allocator,
	temp_allocator := context.temp_allocator,
) {
	context.allocator = allocator
	context.temp_allocator = temp_allocator
	bvh.primitives = primitives
	bvh.max_prims_in_node = max_prims_in_node
	bvh.split_method = split_method

	if len(bvh.primitives) == 0 do return

	primitive_infos := make(
		[dynamic]BVH_Primitive_Info,
		0,
		len(bvh.primitives),
		context.temp_allocator,
	)
	defer delete(primitive_infos)

	for &prim, i in bvh.primitives {
		bounds := hittable_aabb(prim)
		append(
			&primitive_infos,
			BVH_Primitive_Info {
				primitive_number = i,
				bounds = bounds,
				centroid = aabb.centroid(bounds),
			},
		)
	}

	total_nodes: uint = 0
	ordered_primitives := make([dynamic]Hittable, 0, len(bvh.primitives))
	root: ^BVH_Build_Node


	switch split_method {
	case .SAH:
		root = bvh_recursive_build(
			bvh^,
			primitive_infos[:],
			0,
			len(bvh.primitives),
			&total_nodes,
			&ordered_primitives,
		)
	case .HLBVH:
		root = hlbvh_build(
			bvh^,
			primitive_infos[:],
			&total_nodes,
			&ordered_primitives,
			allocator,
			temp_allocator,
		)

	}

	slice.swap_with_slice(bvh.primitives, ordered_primitives[:])

	bvh.nodes = make([]Linear_BVH_Node, total_nodes, allocator)
	offset: uint = 0
	bvh_flatten(bvh^, root, &offset)
}

bvh_flatten :: proc(bvh: BVH, node: ^BVH_Build_Node, offset: ^uint) -> uint {
	linear_node := &bvh.nodes[offset^]
	linear_node.bounds = node.bounds
	my_offset := offset^
	offset^ += 1
	if node.n_primitives > 0 {
		assert(node.children[0] == nil)
		assert(node.children[1] == nil)
		linear_node.offset = node.first_prim_offset
		linear_node.n_primitives = u16(node.n_primitives)
	} else {
		assert(node.children[0] != nil)
		assert(node.children[1] != nil)
		linear_node.axis = u8(node.split_axis)
		linear_node.n_primitives = 0
		bvh_flatten(bvh, node.children[0], offset)
		linear_node.offset = bvh_flatten(bvh, node.children[1], offset)
	}
	return my_offset
}

bvh_recursive_build :: proc(
	bvh: BVH,
	primitive_info: []BVH_Primitive_Info,
	start, end: uint,
	total_nodes: ^uint,
	ordered_prims: ^[dynamic]Hittable,
	allocator := context.allocator,
) -> ^BVH_Build_Node {
	context.allocator = allocator

	node := new(BVH_Build_Node)

	n_primitives := end - start

	total_nodes^ += 1
	bounds := calculate_scene_bounds(primitive_info[start:end])

	if n_primitives == 1 {
		node^ = bvh_create_leaf_node(
			bvh = bvh,
			ordered_prims = ordered_prims,
			primitive_info = primitive_info[start:end],
			n_primitives = n_primitives,
			bounds = bounds,
		)
		return node
	} else {
		centroid_bounds := aabb.empty()
		for i in start ..< end {
			centroid_bounds = aabb.merge(centroid_bounds, primitive_info[i].centroid)
		}
		dim := aabb.maximum_extent(centroid_bounds)

		mid := (start + end) / 2
		axis_value := aabb.axis_interval(centroid_bounds, dim)
		if axis_value.max == axis_value.min {
			node^ = bvh_create_leaf_node(
				bvh = bvh,
				ordered_prims = ordered_prims,
				primitive_info = primitive_info[start:end],
				n_primitives = n_primitives,
				bounds = bounds,
			)
			return node
		} else {
			if n_primitives <= 4 {
				mid = (start + end) / 2

				// TODO improve this function just like the book
				context.user_index = int(dim)
				slice.sort_by(primitive_info[start:end], proc(a, b: BVH_Primitive_Info) -> bool {
					dim := uint(context.user_index)
					return a.centroid[dim] < b.centroid[dim]
				})
			} else {
				buckets: [N_BUCKETS]Bucket_Info

				for i in start ..< end {
					b := int(
						N_BUCKETS * aabb.offset(centroid_bounds, primitive_info[i].centroid)[dim],
					)
					if b == N_BUCKETS do b = N_BUCKETS - 1
					buckets[b].count += 1
					buckets[b].bounds = aabb.merge(buckets[b].bounds, primitive_info[i].bounds)
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
						(f64(count0) * aabb.surface_area(b0) +
								f64(count1) * aabb.surface_area(b1)) /
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

				leaf_cost := n_primitives
				if n_primitives > bvh.max_prims_in_node || min_cost < f64(leaf_cost) {
					mid =
						start +
						split_primitives(
							primitive_info = primitive_info[start:end],
							centroid_bounds = centroid_bounds,
							dim = dim,
							min_cost_split_bucket = min_cost_split_bucket,
						)
				} else {
					node^ = bvh_create_leaf_node(
						bvh = bvh,
						ordered_prims = ordered_prims,
						primitive_info = primitive_info[start:end],
						n_primitives = n_primitives,
						bounds = bounds,
					)
					return node
				}
			}

			init_interior(
				node,
				dim,
				bvh_recursive_build(bvh, primitive_info, start, mid, total_nodes, ordered_prims),
				bvh_recursive_build(bvh, primitive_info, mid, end, total_nodes, ordered_prims),
			)
		}
	}
	return node
}

bvh_hit :: proc(
	bvh: BVH,
	r: ray.Ray,
	inter: interval.Interval,
) -> (
	hit_record: Hit_Record,
	intersected: bool,
) {
	inv_dir := ray.inv_direction(r)
	current_node_index := 0
	buffer: [64]int
	nodes_to_visit: queue.Queue(int)
	queue.init_from_slice(&nodes_to_visit, buffer[:])

	closest_so_far := inter.max

	for {
		node := &bvh.nodes[current_node_index]

		new_inter := interval.Interval {
			min = inter.min,
			max = closest_so_far,
		}
		if aabb.hit(node.bounds, r, new_inter) {
			if node.n_primitives > 0 {
				for i in 0 ..< node.n_primitives {
					i := uint(i)
					if temp_hit_record, temp_intersected := hit(
						bvh.primitives[node.offset + i],
						r,
						new_inter,
					); temp_intersected {
						intersected = true
						closest_so_far = temp_hit_record.t
						hit_record = temp_hit_record
					}
				}

				if next_node, continue_travelling := queue.pop_back_safe(&nodes_to_visit);
				   continue_travelling {
					current_node_index = next_node
				} else do break
			} else {
				if inv_dir[node.axis] < 0 {
					queue.push_back(&nodes_to_visit, current_node_index + 1)
					current_node_index = int(node.offset)
				} else {
					queue.push_back(&nodes_to_visit, int(node.offset))
					current_node_index += 1
				}
			}
		} else {
			if next_node, continue_travelling := queue.pop_back_safe(&nodes_to_visit);
			   continue_travelling {
				current_node_index = next_node
			} else do break
		}
	}

	return
}

init_leaf :: proc(n: ^BVH_Build_Node, first, n_primitives: uint, bounds: aabb.AABB) {
	n.first_prim_offset = first
	n.n_primitives = n_primitives
	n.bounds = bounds
	n.children[0] = nil
	n.children[1] = nil
}

init_interior :: proc(n: ^BVH_Build_Node, axis: uint, c0, c1: ^BVH_Build_Node) {
	n.children[0] = c0
	n.children[1] = c1
	n.bounds = aabb.merge(c0.bounds, c1.bounds)
	n.split_axis = axis
	n.n_primitives = 0
}

@(private)
split_primitives :: proc(
	primitive_info: []$T,
	centroid_bounds: aabb.AABB,
	dim: uint,
	min_cost_split_bucket: uint,
) -> (
	mid: uint,
) {
	Partition_Info :: struct {
		centroid_bounds:       aabb.AABB,
		dim:                   uint,
		min_cost_split_bucket: uint,
	}
	info := Partition_Info {
		centroid_bounds       = centroid_bounds,
		dim                   = dim,
		min_cost_split_bucket = min_cost_split_bucket,
	}
	context.user_ptr = &info
	mid = utils.partition(primitive_info, proc(a: T) -> bool {
		info := cast(^Partition_Info)context.user_ptr
		centroid_bounds := info.centroid_bounds
		dim := info.dim
		b := uint(N_BUCKETS * aabb.offset(centroid_bounds, aabb.centroid(a.bounds))[dim])
		if b == N_BUCKETS do b = N_BUCKETS - 1
		return b <= info.min_cost_split_bucket
	})
	return mid
}

@(private)
@(require_results)
bvh_create_leaf_node :: proc(
	bvh: BVH,
	primitive_info: []BVH_Primitive_Info,
	ordered_prims: ^[dynamic]Hittable,
	bounds: aabb.AABB,
	n_primitives: uint,
) -> BVH_Build_Node {
	first_prim_offset := len(ordered_prims)
	for &prim in primitive_info {
		prim_num := prim.primitive_number
		append(ordered_prims, bvh.primitives[prim_num])
	}
	node: BVH_Build_Node
	init_leaf(&node, uint(first_prim_offset), n_primitives, bounds)
	return node
}

calculate_scene_bounds :: proc(primitive_infos: []BVH_Primitive_Info) -> aabb.AABB {
	bounds := aabb.empty()

	for &info in primitive_infos {
		bounds = aabb.merge(bounds, info.bounds)
	}

	return bounds
}
