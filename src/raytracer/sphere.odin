package raytracer

// import "core:log"
import "core:math/linalg"

Sphere :: struct {
	using primitive: Primitive,
	position:        Vec3,
	radius:          f32,
}

sphere_init :: proc(s: ^Sphere, center: Vec3, radius: f32, material_index: u32) {
	s.position = center
	s.radius = radius
	s.material_index = material_index
	s.box = sphere_aabb(s^)
}

sphere_hit :: proc(
	s: Sphere,
	ray: Ray,
	inter: Interval,
) -> (
	distance: f32,
	normal: Vec3,
	did_hit: bool,
) {
	oc := ray.origin - s.position
	a := linalg.length2(ray.direction)
	b := 2 * linalg.dot(oc, ray.direction)
	c := linalg.length2(oc) - s.radius * s.radius

	discriminant := b * b - 4.0 * a * c
	if discriminant < 0 do return {}, {}, false

	closest_t := (-b - linalg.sqrt(discriminant)) / (2 * a)
	if closest_t > 0.0 && closest_t < inter.max {
		return closest_t, ray.origin + ray.direction * closest_t, true
	}

	return -1, {}, false
}

sphere_aabb :: proc(sphere: Sphere) -> AABB {
	rvec := Vec3{sphere.radius, sphere.radius, sphere.radius}
	f := sphere.position - rvec
	s := sphere.position + rvec
	return AABB{min = linalg.min(f, s), max = linalg.max(f, s)}
}
