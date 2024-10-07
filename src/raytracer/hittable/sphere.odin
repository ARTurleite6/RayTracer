package hittable

import "../interval"
import mat "../material"
import "../ray"
import "../utils"
import "aabb"
import "core:math/linalg"

Sphere :: struct {
	center:   utils.Vec3,
	radius:   f64,
	box:      aabb.AABB,
	material: mat.Material,
}

sphere_init :: proc(s: ^Sphere, center: utils.Vec3, radius: f64, material: mat.Material) {
	s.center = center
	s.radius = radius
	s.material = material
	s.box = sphere_aabb(s^)
}

sphere_hit :: proc(s: Sphere, r: ray.Ray, inter: interval.Interval) -> (Hit_Record, bool) {
	oc := s.center - r.origin
	a := linalg.length2(r.direction)
	h := linalg.dot(r.direction, oc)
	c := linalg.length2(oc) - s.radius * s.radius

	discriminant := h * h - a * c
	if discriminant < 0 do return {}, false

	sqrtd := linalg.sqrt(discriminant)
	root := (h - sqrtd) / a
	if !interval.surrounds(inter, root) {
		root = (h + sqrtd) / a
		if !interval.surrounds(inter, root) do return {}, false
	}

	point := ray.at(r, root)
	hit_record: Hit_Record
	hit_record_init(&hit_record, r, (point - s.center) / s.radius, root, s.material)

	return hit_record, true
}

sphere_aabb :: proc(sphere: Sphere) -> aabb.AABB {
	rvec := utils.Vec3{sphere.radius, sphere.radius, sphere.radius}

	box: aabb.AABB
	aabb.init(&box, sphere.center - rvec, sphere.center + rvec)
	return box
}
