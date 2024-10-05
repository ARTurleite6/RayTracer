package hittable

import "../interval"
import mat "../material"
import "../ray"
import "../utils"
import "aabb"
import "core:math/linalg"

Hit_Record :: struct {
	point:      utils.Vec3,
	normal:     utils.Vec3,
	material:   mat.Material,
	t:          f64,
	front_face: bool,
}

Hittable :: union {
	Hittable_List,
	Sphere,
}

hittable_aabb :: proc(ht: Hittable) -> aabb.AABB {
	switch v in ht {
	case Hittable_List:
		return v.box
	case Sphere:
		return v.box
	}
	return {}
}

hit :: proc(ht: Hittable, r: ray.Ray, inter: interval.Interval) -> (Hit_Record, bool) {
	switch v in ht {
	case Hittable_List:
		return hittable_list_hit(v, r, inter)
	case Sphere:
		return sphere_hit(v, r, inter)
	}

	return {}, false
}

hit_record_init :: proc(
	hit_record: ^Hit_Record,
	r: ray.Ray,
	outward_normal: utils.Vec3,
	t: f64,
	material: mat.Material,
) {
	hit_record.material = material
	hit_record.t = t
	hit_record.point = ray.at(r, t)

	hit_record.front_face = linalg.dot(r.direction, outward_normal) < 0
	hit_record.normal = hit_record.front_face ? outward_normal : -outward_normal
}
