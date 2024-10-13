package scatter

import mat ".."
import "../../color"
import "../../hittable"
import "../../ray"
import "../../utils"
import "core:math/linalg"

scatter :: proc(
	m: mat.Material,
	ray_in: ray.Ray,
	hit_record: hittable.Hit_Record,
) -> (
	ray.Ray,
	color.Color,
	bool,
) {
	switch v in m {
	case mat.Lambertian:
		return lambertian_scatter(v, ray_in, hit_record)
	case mat.Metal:
		return metal_scatter(v, ray_in, hit_record)
	case mat.Dieletric:
		return dieletric_scatter(v, ray_in, hit_record)
	}

	return {}, {}, false
}

dieletric_scatter :: proc(
	m: mat.Dieletric,
	ray_in: ray.Ray,
	hit_record: hittable.Hit_Record,
) -> (
	ray.Ray,
	color.Color,
	bool,
) {
	ri := hit_record.front_face ? (1.0 / m.refraction_index) : m.refraction_index

	uniform_direction := linalg.normalize(ray_in.direction)
	cos_theta := linalg.dot(hit_record.normal, -uniform_direction)
	sin_theta := linalg.sqrt(1.0 - cos_theta * cos_theta)

	cannot_refract := ri * sin_theta > 1.0

	direction: utils.Vec3
	if cannot_refract || utils.refletance(cos_theta, ri) > utils.random_double() {
		direction = linalg.reflect(uniform_direction, hit_record.normal)
	} else {
		direction = linalg.refract(uniform_direction, hit_record.normal, ri)
	}

	return ray.Ray{origin = hit_record.point, direction = direction},
		color.Color{1.0, 1.0, 1.0},
		true
}

metal_scatter :: proc(
	m: mat.Metal,
	ray_in: ray.Ray,
	hit_record: hittable.Hit_Record,
) -> (
	ray.Ray,
	color.Color,
	bool,
) {
	reflection := linalg.reflect(ray_in.direction, hit_record.normal)
	reflection = linalg.normalize(reflection) + (m.fuzz * utils.random_unit_vector())
	scattered := ray.Ray {
		origin    = hit_record.point,
		direction = reflection,
	}
	return scattered, m.albedo, linalg.dot(scattered.direction, hit_record.normal) > 0.0
}

lambertian_scatter :: proc(
	mat: mat.Lambertian,
	ray_in: ray.Ray,
	hit_record: hittable.Hit_Record,
) -> (
	ray.Ray,
	color.Color,
	bool,
) {
	scatter_direction := hit_record.normal + utils.random_unit_vector()

	if utils.almost_zero(scatter_direction) {
		scatter_direction = hit_record.normal
	}

	scatter_ray := ray.Ray {
		origin    = hit_record.point,
		direction = scatter_direction,
	}


	color := mat.albedo

	return scatter_ray, color, true
}
