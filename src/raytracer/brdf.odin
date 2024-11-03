package raytracer

import "core:log"
import "core:math"
import "core:math/linalg"
_ :: log

cook_torrance_brdf_sample :: proc(
	material: Material,
	wo: Vec3,
	normal: Vec3,
	rand: Vec2,
) -> (
	f: Vec3,
	pdf: f32,
	wi: Vec3,
) {
	alpha := material.roughness * material.roughness

	wh := cook_torrance_sample_wh(alpha, normal, rand)
	wi = linalg.reflect(-wo, wh)

	f, pdf = cook_torrance_brdf_eval(material, alpha, normal, wo, wi, wh)

	return f, pdf, wi
}

cook_torrance_brdf_eval :: proc(
	material: Material,
	alpha: f32,
	n, wo, wi, h: Vec3,
) -> (
	Vec3,
	f32,
) {

	f0 := linalg.mix(Vec3{0.04, 0.04, 0.04}, material.albedo, material.metallic)

	ndotv := max(linalg.dot(n, wo), 0)
	ndotl := max(linalg.dot(n, wi), 0)
	ndoth := max(linalg.dot(n, h), 0)
	hdotv := max(linalg.dot(h, wo), 0)

	d := d(ndoth, alpha)
	g := g(ndotv, ndotl, alpha)
	f := fresnel_schlick(hdotv, f0)

	specular := (f * d * g) / (4.0 * ndotv * ndotl + 0.0001)
	kd := Vec3{1, 1, 1} - f
	kd *= 1.0 - material.metallic

	diffuse := material.albedo * kd * INV_PI

	pdf := d * ndoth / (4 * hdotv + 0.0001)

	return diffuse + specular, pdf
}

d :: proc(alpha: f32, ndoth: f32) -> f32 {
	a2 := alpha * alpha

	ndoth2 := ndoth * ndoth

	nom := a2
	denom := (ndoth2 * (a2 - 1) + 1)
	denom = max(math.PI * denom * denom, 0.001)

	return nom / denom
}

g_schlick :: proc(ndotv: f32, alpha: f32) -> f32 {
	r := alpha + 1
	k := (r * r) / 8
	nom := ndotv
	denom := ndotv * (1 - k) + k
	return nom / denom
}

g :: proc(ndotv, ndotl, alpha: f32) -> f32 {
	gg1 := g_schlick(ndotv, alpha)
	gg2 := g_schlick(ndotl, alpha)

	return gg1 * gg2
}

cook_torrance_sample_wh :: proc(alpha: f32, normal: Vec3, rand: Vec2) -> Vec3 {
	phi := (2 * math.PI) * rand.y
	theta := math.atan(alpha * math.sqrt(rand.x / (1 - rand.x)))

	cos_theta := math.cos(theta)
	sin_theta := math.sin(theta)

	w := Vec3{sin_theta * linalg.cos(phi), sin_theta * linalg.sin(phi), cos_theta}

	onb := make_onb(normal)
	return linalg.normalize(onb_transform(onb, w))
}

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
