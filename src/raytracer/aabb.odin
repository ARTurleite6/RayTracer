package raytracer

import "core:log"
import "core:math"
import "core:math/linalg"
_ :: log

AABB :: struct {
	min, max: Vec3,
}

@(require_results)
create_empty_aabb :: proc() -> AABB {
	return {
		min = {math.F32_MAX, math.F32_MAX, math.F32_MAX},
		max = {-math.F32_MAX, -math.F32_MAX, -math.F32_MAX},
	}
}

@(require_results)
merge_aabb :: proc(b1, b2: AABB) -> AABB {
	return {min = linalg.min(b1.min, b2.min), max = linalg.max(b1.max, b2.max)}
}

@(require_results)
aabb_hit :: proc(aabb: AABB, r: Ray, r_interval: Interval) -> bool {
	r_interval := r_interval
	origin := r.origin
	direction := r.direction

	for axis in 0 ..< 3 {
		axis := uint(axis)
		inv_d := 1.0 / direction[axis]

		t0 := (aabb.min[axis] - origin[axis]) * inv_d
		t1 := (aabb.max[axis] - origin[axis]) * inv_d

		if t0 > t1 {
			t0, t1 = t1, t0
		}

		r_interval.min = max(r_interval.min, t0)
		r_interval.max = min(r_interval.max, t1)

		if r_interval.min > r_interval.max {
			return false
		}
	}

	return true
}
