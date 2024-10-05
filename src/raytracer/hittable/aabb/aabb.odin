package aabb

import "../../interval"
import "../../ray"
import "../../utils"
import "core:fmt"
import "core:math"

AABB :: struct {
	x, y, z: interval.Interval,
}

init :: proc(aabb: ^AABB, a, b: utils.Vec3) {
	aabb.x =
		(a.x <= b.x) ? interval.Interval{min = a.x, max = b.x} : interval.Interval{min = b.x, max = a.x}
	aabb.y =
		(a.y <= b.y) ? interval.Interval{min = a.y, max = b.y} : interval.Interval{min = b.y, max = a.y}
	aabb.z =
		(a.z <= b.z) ? interval.Interval{min = a.z, max = b.z} : interval.Interval{min = b.z, max = a.z}
}

merge :: proc(b1: AABB, b2: AABB) -> AABB {
	return {
		x = interval.between(b1.x, b2.x),
		y = interval.between(b1.y, b2.y),
		z = interval.between(b1.z, b2.z),
	}
}

hit :: proc(aabb: AABB, r: ray.Ray, r_interval: interval.Interval) -> bool {
	r_interval := r_interval
	t0 := r_interval.min
	t1 := r_interval.max
	origin := r.origin
	direction := r.direction

	for axis in 0 ..< 3 {
		ax := axis_interval(aabb, axis)
		adinv := 1.0 / direction[axis]
		tnear := (ax.min - origin[axis]) * adinv
		tfar := (ax.max - origin[axis]) * adinv

		if tnear > tfar {}

		tmin := min(t1, t2)
		tmax := max(t1, t2)
		r_interval.min = max(tmin, r_interval.min)
		r_interval.max = min(tmax, r_interval.max)
		fmt.println(r_interval)

		if r_interval.max <= r_interval.min {
			return false
		}
	}

	return true
}

axis_interval :: proc(aabb: AABB, axis: int) -> interval.Interval {
	if axis == 0 {
		return aabb.x
	} else if axis == 1 {
		return aabb.y
	} else {
		return aabb.z
	}
}
