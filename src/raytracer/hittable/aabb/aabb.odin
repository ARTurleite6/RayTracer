package aabb

import "../../interval"
import "../../ray"
import "../../utils"

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
	t_min := r_interval.min
	t_max := r_interval.max

	origin := r.origin
	direction := r.direction

	for axis in 0 ..< 3 {
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

axis_interval :: proc(aabb: AABB, axis: int) -> interval.Interval {
	if axis == 0 {
		return aabb.x
	} else if axis == 1 {
		return aabb.y
	} else {
		return aabb.z
	}
}
