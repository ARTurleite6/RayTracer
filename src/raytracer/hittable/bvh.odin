package hittable

import "../interval"
import "../ray"
import "aabb"
import "core:slice"

BVH :: struct {
	nodes: [dynamic]Node,
	root:  Maybe(int),
}

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
