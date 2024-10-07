package hittable

import "../interval"
import "../ray"
import "aabb"
import "core:mem"

Hittable_List :: struct {
	hittables: [dynamic]Hittable,
	box:       aabb.AABB,
}

hittable_list_init :: proc(hittable_list: ^Hittable_List) {
	hittable_list.hittables = make([dynamic]Hittable)
}

hittable_list_add :: proc(
	hittable_list: ^Hittable_List,
	hittable: Hittable,
) -> mem.Allocator_Error {
	_, err := append(&hittable_list.hittables, hittable)

	hittable_list.box = aabb.merge(hittable_list.box, hittable_aabb(hittable))

	new_box := hittable_aabb(hittable)
	if len(hittable_list.hittables) == 1 {
		hittable_list.box = new_box
	} else {
		hittable_list.box = aabb.merge(hittable_list.box, new_box)
	}
	return err
}

hittable_list_hit :: proc(
	ht: Hittable_List,
	r: ray.Ray,
	inter: interval.Interval,
) -> (
	rec: Hit_Record,
	hitted: bool,
) {
	closest_so_far := inter.max

	for &object in ht.hittables {
		if temp_hit_record, temp_hitted := hit(
			object,
			r,
			interval.Interval{min = inter.min, max = closest_so_far},
		); temp_hitted {
			hitted = true
			closest_so_far = temp_hit_record.t
			rec = temp_hit_record
		}
	}

	return
}

hittable_list_clear :: proc(hittable_list: ^Hittable_List) {
	clear(&hittable_list.hittables)
}

hittable_list_destroy :: proc(hittable_list: ^Hittable_List) {
	delete(hittable_list.hittables)
	hittable_list.hittables = nil
}
