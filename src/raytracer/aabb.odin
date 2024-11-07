package raytracer

AABB :: struct {
	x, y, z: Interval,
}

create_aabb :: proc(a, b: Vec3) -> AABB {
	return {
		x = (a.x <= b.x) ? Interval{min = a.x, max = b.x} : Interval{min = b.x, max = a.x},
		y = (a.y <= b.y) ? Interval{min = a.y, max = b.y} : Interval{min = b.y, max = a.y},
		z = (a.z <= b.z) ? Interval{min = a.z, max = b.z} : Interval{min = b.z, max = a.z},
	}
}

aabb_centroid :: proc(box: AABB) -> Vec3 {
	min_vec, max_vec := aabb_min_max_vecs(box)
	return 0.5 * min_vec + 0.5 * max_vec
}

aabb_empty :: proc() -> AABB {
	return {x = empty_interval(), y = empty_interval(), z = empty_interval()}
}

aabb_merge :: proc {
	aabb_merge_with_box,
	aabb_merge_with_point,
}

aabb_merge_with_point :: proc(b: AABB, p: Vec3) -> AABB {
	return {
		x = {min = min(b.x.min, p.x), max = max(b.x.max, p.x)},
		y = {min = min(b.y.min, p.y), max = max(b.y.max, p.y)},
		z = {min = min(b.z.min, p.z), max = max(b.z.max, p.z)},
	}
}

aabb_merge_with_box :: proc(b1: AABB, b2: AABB) -> AABB {
	return {
		x = interval_between(b1.x, b2.x),
		y = interval_between(b1.y, b2.y),
		z = interval_between(b1.z, b2.z),
	}
}

aabb_min_max_vecs :: proc(box: AABB) -> (min: Vec3, max: Vec3) {
	min = {box.x.min, box.y.min, box.z.min}
	max = {box.x.max, box.y.max, box.z.max}
	return
}

aabb_diagonal :: proc(b: AABB) -> Vec3 {
	min, max := aabb_min_max_vecs(b)
	return max - min
}

aabb_surface_area :: proc(b: AABB) -> f32 {
	d := aabb_diagonal(b)
	return 2 * (d.x * d.y + d.x * d.z + d.y * d.z)
}

aabb_maximum_extent :: proc(b: AABB) -> uint {
	d := aabb_diagonal(b)
	if d.x > d.y && d.x > d.z {
		return 0
	} else if d.y > d.z {
		return 1
	} else {
		return 2
	}
}

aabb_longest_axis :: proc(a: AABB) -> int {
	x_size := interval_size(a.x)
	y_size := interval_size(a.y)
	z_size := interval_size(a.z)

	if x_size > y_size {
		return x_size > z_size ? 0 : 2
	} else {
		return y_size > z_size ? 1 : 2
	}
}

aabb_hit :: proc(aabb: AABB, r: Ray, r_interval: Interval) -> bool {
	t_min := r_interval.min
	t_max := r_interval.max

	origin := r.origin
	direction := r.direction

	for axis in 0 ..< 3 {
		axis := uint(axis)
		ax := aabb_axis_interval(aabb, axis)
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

aabb_contains :: proc(outer, inner: AABB) -> bool {
	return(
		interval_contains(outer.x, inner.x) &&
		interval_contains(outer.y, inner.y) &&
		interval_contains(outer.z, inner.z) \
	)
}

aabb_offset :: proc(box: AABB, point: Vec3) -> Vec3 {
	min, max := aabb_min_max_vecs(box)
	o := point - min
	if max.x > min.x do o.x /= max.x - min.x
	if max.y > min.y do o.y /= max.y - min.y
	if max.z > min.z do o.z /= max.z - min.z
	return o
}

aabb_axis_interval :: proc(aabb: AABB, axis: uint) -> Interval {
	if axis == 0 {
		return aabb.x
	} else if axis == 1 {
		return aabb.y
	} else {
		return aabb.z
	}
}
