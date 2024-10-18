package ray

import "../utils"
import "core:math/linalg"

Ray :: struct {
	origin:    utils.Vec3,
	direction: utils.Vec3,
}

at :: proc(r: Ray, t: f64) -> utils.Vec3 {
	return r.origin + t * r.direction
}

hit_sphere :: proc(r: Ray, center: utils.Vec3, radius: f64) -> f64 {
	dot :: linalg.dot

	oc := center - r.origin
	a := linalg.length2(r.direction)
	h := linalg.dot(r.direction, oc)
	c := linalg.length2(oc) - linalg.pow(radius, 2)
	discriminant := h * h - a * c
	if discriminant < 0.0 {
		return -1.0
	} else {
		return h - linalg.sqrt(discriminant) / a
	}
}

inv_direction :: proc(r: Ray) -> utils.Vec3 {
	return {
		1 / r.direction.x,
		1 / r.direction.y,
		1 / r.direction.z,
	}
}