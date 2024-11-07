package raytracer

import "core:log"
import "core:math/linalg"
_ :: log

Triangle :: struct {
	box:    AABB,
	points: [3]Vec3,
	normal: Vec3,
}

triangle_init :: proc(t: ^Triangle, points: [3]Vec3) {
	t.points = points
	t.box = AABB {
		min = linalg.min(t.points[0], t.points[1], t.points[2]),
		max = linalg.max(t.points[0], t.points[1], t.points[2]),
	}
	t.normal = linalg.normalize(linalg.cross(t.points[1] - t.points[0], t.points[2] - t.points[0]))
}

triangle_hit :: proc(
	t: Triangle,
	ray: Ray,
	interval: Interval,
) -> (
	distance: f32,
	normal: Vec3,
	did_hit: bool,
) {
	if !aabb_hit(t.box, ray, interval) {
		return
	}

	e1 := t.points[1] - t.points[0]
	e2 := t.points[2] - t.points[0]

	r_cross_e2 := linalg.cross(ray.direction, e2)
	det := linalg.dot(e1, r_cross_e2)

	if det > -linalg.F32_EPSILON && det < linalg.F32_EPSILON {
		return
	}

	inv_det := 1 / det
	s := ray.origin - t.points[0]
	u := inv_det * linalg.dot(s, r_cross_e2)

	s_cross_e1 := linalg.cross(s, e1)
	v := inv_det * linalg.dot(ray.direction, s_cross_e1)
	if u < 0 || u > 1 || v < 0 || u + v > 1 {
		return
	}

	hit_distance := inv_det * linalg.dot(e2, s_cross_e1)

	if hit_distance > linalg.F32_EPSILON && hit_distance < interval.max {
		normal = t.normal
		if linalg.dot(-ray.direction, normal) < 0 do normal = -normal
		return hit_distance, normal, true
	}
	return
}
