package aabb

import "../../interval"
import "../../ray"
import "../../utils"

AABB :: struct {
	x, y, z: interval.Interval,
}

create :: proc(a, b: utils.Vec3) -> AABB {
	return {
		x = (a.x <= b.x) ? interval.Interval{min = a.x, max = b.x} : interval.Interval{min = b.x, max = a.x},
		y = (a.y <= b.y) ? interval.Interval{min = a.y, max = b.y} : interval.Interval{min = b.y, max = a.y},
		z = (a.z <= b.z) ? interval.Interval{min = a.z, max = b.z} : interval.Interval{min = b.z, max = a.z},
	}
}

centroid :: proc(box: AABB) -> utils.Vec3 {
	min_vec, max_vec := min_max_vecs(box)
	return 0.5 * min_vec + 0.5 * max_vec
}

empty :: proc() -> AABB {
	return {x = interval.empty(), y = interval.empty(), z = interval.empty()}
}

merge :: proc {
	merge_with_box,
	merge_with_point,
}

merge_with_point :: proc(b: AABB, p: utils.Vec3) -> AABB {
	return {
		x = {min = min(b.x.min, p.x), max = max(b.x.max, p.x)},
		y = {min = min(b.y.min, p.y), max = max(b.y.max, p.y)},
		z = {min = min(b.z.min, p.z), max = max(b.z.max, p.z)},
	}
}

merge_with_box :: proc(b1: AABB, b2: AABB) -> AABB {
	return {
		x = interval.between(b1.x, b2.x),
		y = interval.between(b1.y, b2.y),
		z = interval.between(b1.z, b2.z),
	}
}

min_max_vecs :: proc(box: AABB) -> (min: utils.Vec3, max: utils.Vec3) {
	min = {box.x.min, box.y.min, box.z.min}
	max = {box.x.max, box.y.max, box.z.max}
	return
}

diagonal :: proc(b: AABB) -> utils.Vec3 {
	min, max := min_max_vecs(b)
	return max - min
}

surface_area :: proc(b: AABB) -> f64 {
	d := diagonal(b)
	return 2 * (d.x * d.y + d.x * d.z + d.y * d.z)
}

maximum_extent :: proc(b: AABB) -> uint {
	d := diagonal(b)
	if d.x > d.y && d.x > d.z {
		return 0
	} else if d.y > d.z {
		return 1
	} else {
		return 2
	}
}

longest_axis :: proc(a: AABB) -> int {
	x_size := interval.size(a.x)
	y_size := interval.size(a.y)
	z_size := interval.size(a.z)

	if x_size > y_size {
		return x_size > z_size ? 0 : 2
	} else {
		return y_size > z_size ? 1 : 2
	}
}

hit :: proc(aabb: AABB, r: ray.Ray, r_interval: interval.Interval) -> bool {
	t_min := r_interval.min
	t_max := r_interval.max

	origin := r.origin
	direction := r.direction

	for axis in 0 ..< 3 {
		axis := uint(axis)
		ax := axis_interval(aabb, axis)
		inv_d := 1.0 / direction[axis]
		t0 := (ax.min - origin[axis]) * inv_d
		t1 := (ax.max - origin[axis]) * inv_d

		if inv_d < 0 {
			t0, t1 = t1, t0
		}

		t_min = max(t0, t_min)
		t_max = min(t1, t_max)

		if t_max <= t_min {
			return false
		}
	}

	return true
}

contains :: proc(outer, inner: AABB) -> bool {
	return(
		interval.contains(outer.x, inner.x) &&
		interval.contains(outer.y, inner.y) &&
		interval.contains(outer.z, inner.z) \
	)
}

offset :: proc(box: AABB, point: utils.Vec3) -> utils.Vec3 {
	min, max := min_max_vecs(box)
	o := point - min
	if max.x > min.x do o.x /= max.x - min.x
	if max.y > min.y do o.y /= max.y - min.y
	if max.z > min.z do o.z /= max.z - min.z
	return o
}

axis_interval :: proc(aabb: AABB, axis: uint) -> interval.Interval {
	if axis == 0 {
		return aabb.x
	} else if axis == 1 {
		return aabb.y
	} else {
		return aabb.z
	}
}
