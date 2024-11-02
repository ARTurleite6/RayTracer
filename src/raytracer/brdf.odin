package raytracer

import "core:math/linalg"

lambertian_brdf_sample :: proc(
	material: Material,
	normal: Vec3,
	rand: Vec2,
) -> (
	scattered: Vec3,
	f: Vec3,
	pdf: f32,
) {
	uvw := make_onb(normal)

	scattered = onb_transform(uvw, random_cosine_direction(rand))
	pdf = lambertian_pdf(scattered, normal)
	f = lambertian_eval(material, scattered, normal)
	return scattered, f, pdf
}

@(private = "file")
lambertian_pdf :: proc "contextless" (wi, normal: Vec3) -> f32 {
	return linalg.dot(wi, normal) * INV_PI
}

@(private = "file")
lambertian_eval :: proc "contextless" (
	material: Material,
	input_direction: Vec3,
	normal: Vec3,
) -> Vec3 {
	return material.albedo * INV_PI
}

fresnel_schlick :: proc "contextless" (cosTheta: f32, F0: Vec3) -> Vec3 {
	return F0 + (1.0 - F0) * linalg.pow((1.0 + 0.000001) - cosTheta, 5.0)
}
