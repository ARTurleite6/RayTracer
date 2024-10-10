package hittable

import "../interval"
import "../ray"
import "../utils"
import "aabb"
import "core:slice"

BVH :: struct {
	max_prims_in_node: int,
	split_method:      Split_Method,
	primitives:        []Hittable,
	nodes:             [dynamic]Node,
	root:              Maybe(int),
}

bvh_init :: proc(
	bvh: ^BVH,
	primitives: []Hittable,
	max_prims_in_node: int,
	split_method: Split_Method,
	allocator := context.allocator,
) {
	context.allocator = allocator
	bvh.primitives = primitives
	bvh.max_prims_in_node = max_prims_in_node
	bvh.split_method = split_method

	if len(bvh.primitives) == 0 do return

	primitive_infos := make([dynamic]BVH_Primitive_Info, 0, len(bvh.primitives))
	for i, &prim in bvh.primitives {
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

	total_nodes := 0
	ordered_primitives := make([dynamic]Hittable, 0, len(bvh.primitives))
	root: ^BVH_Build_Node

	if split_method == .SAH {

	}
}

bvh_recursive_build :: proc(
	bvh: BVH,
	primitive_info: []BVH_Primitive_Info,
	start, end: int,
	total_nodes: ^int,
	ordered_prims: [dynamic]Hittable,
	allocator := context.allocator,
) {
	context.allocator = allocator

	node := new(BVH_Build_Node)
	total_nodes^ += 1
	bounds := aabb.empty()
	for i in start ..< end {
		bounds = aabb.merge(bounds, primitive_info[i].bounds)
	}

	n_primitives := end - start
	if n_primitives == 1 {
		first_prim_offset = len(ordered_prims)
		for i in start ..< end {
			prim_num := primitive_info[i].primitive_number
			append(&ordered_prims, bvh.primitives[prim_num])
		}
		init_leaf(node, first_prim_offset, bounds)
		return node
	} else {
		centroid_bounds := aabb.empty()
		for i in start ..< end {
			centroid_bounds := aabb.merge(centroid_bounds, primitive_info[i].bounds)
		}
		dim := aabb.maximum_extent(centroid_bounds)

		mid := (start + end) / 2
		axis_value := aabb.axis_internal(centroid_bounds, dim)
		if axis_value.max == axis_value.min {
			first_prim_offset := len(ordered_prims)
			for i in start ..< end {
				prim_num := primitive_info[i].primitive_number
				append(&ordered_prims, bvh.primitives[prim_num])
			}
			init_leaf(node, first_prim_offset, n_primitives, bounds)
			return node
		} else {
			if n_primitives <= 4 {
				mid = (start + end) / 2

				slice.sort_by(primitive_info[start:end], proc(a, b: BVH_Primitive_Info) -> bool {
					return a.centroid[dim] < b.centroid[dim]
				})
			} else {
				n_buckets :: 12
				Bucket_Info :: struct {
					cout:   int,
					bounds: aabb.AABB,
				}
				buckets: [n_buckets]Bucket_Info

				for i in start ..< end {
					b := n_buckets * aabb.offset(primitive_info[i].centroid)[dim]
					if b == n_buckets do b = n_buckets - 1
					buckets[b].count += 1
					buckets[b].bounds = abb.merge(buckets[b].bounds, primitive_info[i].bounds)
				}

				cost: [n_buckets - 1]f64
				for i in 0 ..< n_buckets - 1 {
					b0, b1 := aabb.empty(), aabb.empty()
					count0, count1: int
					for j in j ..= i {
						b0 = aabb.merge(b0, buckets[j].bounds)
						count0 += buckets[j].count
					}

					for j in (i + 1) ..< n_buckets {
						b1 = aabb.merge(b1, buckets[j].bounds)
						count1 += buckets[j].count
					}

					cost[i] =
						0.125 +
						(count0 * surface_area(b0) + count1 * surface_area(b1)) /
							surface_area(bounds)
				}

				min_cost := cost[0]
				min_cost_split_bucket := 0
				for i in 1 ..< n_buckets - 1 {
					if cost[i] < min_cost {
						min_cost = cost[i]
						min_cost_split_bucket = i
					}
				}

				leaf_cost = n_primitives
				if n_primitives > bvh.max_prims_in_node || min_cost < leaf_cost {
					// TODO partition this
				} else {
					first_prim_offset := len(ordered_prims)
					for i in start ..< end {
						prim_num := primitive_info[i].primitive_number
						append(&ordered_prims, bvh.primitives[prim_num])
					}
					init_leaf(node, first_prim_offset, n_primitives, bounds)
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
	children:                                    []^BVH_Build_Node,
	split_axis, first_prim_offset, n_primitives: int,
}

init_leaf :: proc(n: ^BVH_Build_Node, first, n_primitives: int, bounds: aabb.AABB) {
	n.first_prim_offset = first
	n.n_primitives = n_primitives
	n.bounds = bounds
	n.children[0] = nil
	n.children[1] = nil
}

init_interior :: proc(n: ^BVH_Build_Node, axis: int, c0, c1: ^BVH_Build_Node) {
	children[0] = c0
	children[1] = c1
	n.bounds = aabb.merge(c0.bounds, c1.bounds)
	n.split_axis = axis
	n.n_primitives = 0
}

recursive_build :: proc()

Node :: struct {
	box:         aabb.AABB,
	left, right: Maybe(int),
	object:      Maybe(^Hittable),
}

Algorigthm :: enum {
	SpatialMedianSplit,
	SurfaceAreaHeuristic,
}

bvh_init :: proc(
	bvh: ^BVH,
	objects: []Hittable,
	allocator := context.allocator,
	algorithm := Algorigthm.SpatialMedianSplit,
) {
	num_nodes := len(objects) * 2 - 1
	if num_nodes > 0 {
		bvh.nodes = make([dynamic]Node, 0, num_nodes, allocator = allocator)
		bvh.root = bvh_build(bvh, objects, 0, len(objects), algorithm)
	}
}

bvh_destroy :: proc(bvh: ^BVH) {
	delete(bvh.nodes)
	bvh.nodes = nil
}

bvh_build :: proc(
	bvh: ^BVH,
	objects: []Hittable,
	start, end: int,
	algorithm: Algorigthm,
	gen := context.random_generator,
) -> Maybe(int) {
	context.random_generator = gen
	node_index := len(bvh.nodes)
	append(&bvh.nodes, Node{})
	node := &bvh.nodes[node_index]

	node.box = aabb.empty()
	for &obj in objects[start:end] {
		node.box = aabb.merge(node.box, hittable_aabb(obj))
	}

	object_span := end - start

	if object_span == 1 {
		node.left = nil
		node.right = nil
		node.object = &objects[start]
	} else {
		mid: int
		axis := aabb.longest_axis(node.box)
		context.user_index = axis
		comparator := proc(a, b: Hittable) -> slice.Ordering {
			axis := context.user_index
			return box_compare(a, b, axis)
		}
		slice.sort_by_cmp(objects[start:end], comparator)
		switch algorithm {
		case .SpatialMedianSplit:
			mid = start + (object_span / 2)
		case .SurfaceAreaHeuristic:
			mid = sah_split(objects, start, end, node.box)
		}
		node.left = bvh_build(bvh, objects, start, mid, algorithm)
		node.right = bvh_build(bvh, objects, mid, end, algorithm)
	}

	return node_index
}

bvh_hit :: proc(b: BVH, r: ray.Ray, ray_t: interval.Interval) -> (Hit_Record, bool) {
	return _bvh_hit(b, b.root, r, ray_t)
}

@(private)
sah_split :: proc(objects: []Hittable, start, end: int, box: aabb.AABB) -> int {
	object_span := end - start
	best_cost := max(f64)
	best_split := start

	parent_area := surface_area(box)
	inv_parent_area := 1.0 / parent_area

	for axis in 0 ..= 2 {
		context.user_index = axis
		slice.sort_by_cmp(objects[start:end], proc(a, b: Hittable) -> slice.Ordering {
			axis := context.user_index
			return box_compare(a, b, axis)
		})

		left_box := aabb.empty()
		left_count := 0
		right_count := object_span

		for i in 0 ..< object_span - 1 {
			obj := &objects[start + i]
			left_box = aabb.merge(left_box, hittable_aabb(obj^))
			left_count += 1
			right_count -= 1

			right_box := aabb.empty()
			if i + 1 < object_span {
				for j in i + 1 ..< object_span {
					right_box = aabb.merge(right_box, hittable_aabb(objects[start + j]))
				}
			}

			left_prob := surface_area(left_box) * inv_parent_area
			right_prob := surface_area(right_box) * inv_parent_area

			cost := 1.0 + (f64(left_count) * left_prob + f64(right_count) * right_prob)

			if cost < best_cost {
				best_cost = cost
				best_split = start + i + 1
			}
		}
	}

	return best_split
}

@(private)
surface_area :: proc(box: aabb.AABB) -> f64 {
	min_vec, max_vec := aabb.min_max_vecs(box)
	extent := min_vec - max_vec

	return 2 * (extent.x * extent.y + extent.x * extent.z + extent.y * extent.z)
}

@(private)
_bvh_hit :: proc(
	b: BVH,
	node_index: Maybe(int),
	r: ray.Ray,
	ray_t: interval.Interval,
) -> (
	Hit_Record,
	bool,
) {
	node_index, has_node := node_index.(int)
	if !has_node {
		return {}, false
	}

	node := &b.nodes[node_index]

	if !aabb.hit(node.box, r, ray_t) {
		return {}, false
	}

	if obj, ok := node.object.(^Hittable); ok {
		// leaf node
		return hit(obj^, r, ray_t)
	}

	hit_left, found_left := _bvh_hit(b, node.left, r, ray_t)
	closest_so_far := ray_t.max
	if found_left {
		closest_so_far = hit_left.t
	}

	hit_right, found_right := _bvh_hit(
		b,
		node.right,
		r,
		interval.Interval{min = ray_t.min, max = closest_so_far},
	)

	if found_right {
		return hit_right, true
	}

	if found_left {
		return hit_left, true
	}

	return {}, false
}

@(private)
box_compare :: proc(a, b: Hittable, axis: int) -> slice.Ordering {
	box_a := hittable_aabb(a)
	box_b := hittable_aabb(b)
	centroid_a := aabb.centroid(box_a)
	centroid_b := aabb.centroid(box_b)

	if centroid_a[axis] < centroid_b[axis] {
		return .Less
	} else if centroid_a[axis] > centroid_b[axis] {
		return .Greater
	} else {
		return .Equal
	}
}
