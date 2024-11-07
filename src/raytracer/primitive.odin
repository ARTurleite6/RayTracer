package raytracer

Primitive :: struct {
	material_index: u32,
	box:            AABB,
}

hit :: proc {
	primitive_list_hit,
	triangle_hit,
	mesh_hit,
	sphere_hit,
}

primitive_list_hit :: proc(
	primitives: []$T,
	ray: Ray,
	interval: Interval,
) -> (
	distance: f32,
	closest_primitive: int,
	normal: Vec3,
	did_hit: bool,
) {
	closest_primitive = -1

	hit_distance := interval.max

	hit_normal: Vec3
	for &primitive, i in primitives {
		if distance, hit_normal, did_hit = hit(
			primitive,
			ray,
			Interval{min = interval.min, max = hit_distance},
		); did_hit {
			hit_distance = distance
			closest_primitive = i
			normal = hit_normal
		}
	}

	return hit_distance, closest_primitive, normal, closest_primitive >= 0
}
