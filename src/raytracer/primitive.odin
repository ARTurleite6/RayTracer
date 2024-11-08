package raytracer

Primitive :: struct {
	material_index: u32,
	box:            AABB,
	variant:        union {
		Sphere,
		Mesh,
	},
}

primitive_init :: proc {
	primitive_mesh_init,
	primitive_sphere_init,
}

primitive_sphere_init :: proc(
	primitive: ^Primitive,
	position: Vec3,
	radius: f32,
	material_index: u32,
) {
	primitive.material_index = material_index
	sphere: Sphere
	sphere_init(&sphere, position, radius)
	primitive.variant = sphere
	primitive.box = sphere_aabb(sphere)
}

primitive_mesh_init :: proc(primitive: ^Primitive, triangles: []Triangle, material_index: u32) {
	primitive.material_index = material_index
	mesh: Mesh
	mesh_init(&mesh, triangles)
	primitive.variant = mesh
	primitive.box = mesh_aabb(mesh)
}

hit :: proc {
	soa_primitive_list_hit,
	primitive_list_hit,
	primitive_hit,
	triangle_hit,
	mesh_hit,
	sphere_hit,
}

primitive_hit :: proc(
	primitive: Primitive,
	ray: Ray,
	interval: Interval,
) -> (
	distance: f32,
	normal: Vec3,
	did_hit: bool,
) {
	if !aabb_hit(primitive.box, ray, interval) {
		return
	}

	switch v in primitive.variant {
	case Mesh:
		return hit(v, ray, interval)
	case Sphere:
		return hit(v, ray, interval)
	}

	return
}

soa_primitive_list_hit :: proc(
	primitives: #soa[]$T,
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

primitive_list_hit :: proc(
	primitives: $T/[]$E,
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
