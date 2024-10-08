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

bvh_init :: proc(bvh: ^BVH, objects: []Hittable, allocator := context.allocator) {
	num_nodes := len(objects) * 2 - 1
	if num_nodes > 0 {
		bvh.nodes = make([dynamic]Node, 0, num_nodes, allocator = allocator)
		bvh.root = bvh_build(bvh, objects, 0, len(objects))
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

	axis := aabb.longest_axis(node.box)
	context.user_index = axis
	comparator := proc(a, b: Hittable) -> slice.Ordering {
		axis := context.user_index
		return box_compare(a, b, axis)
	}

	object_span := end - start

	if object_span == 1 {
		node.left = nil
		node.right = nil
		node.object = &objects[start]
	} else if object_span == 2 {
		node.left = bvh_build(bvh, objects, start, start + 1)
		node.right = bvh_build(bvh, objects, start + 1, end)
	} else {
		slice.sort_by_cmp(objects[start:end], comparator)

		mid := start + (object_span / 2)
		node.left = bvh_build(bvh, objects, start, mid)
		node.right = bvh_build(bvh, objects, mid, end)
	}

	return node_index
}

bvh_hit :: proc(b: BVH, r: ray.Ray, ray_t: interval.Interval) -> (Hit_Record, bool) {
	return _bvh_hit(b, b.root, r, ray_t)
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

	a_min := aabb.axis_interval(box_a, axis).min
	b_min := aabb.axis_interval(box_b, axis).min

	if a_min < b_min {
		return .Less
	} else if a_min > b_min {
		return .Greater
	} else {
		return .Equal
	}
}
