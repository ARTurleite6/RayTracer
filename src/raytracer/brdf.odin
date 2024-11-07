package raytracer

import "core:log"
import "core:math"
import "core:math/linalg"
_ :: log

multi_brdf_sample :: proc(
	material: Material,
	wo: Vec3,
	rand: Vec2,
) -> (
	f: Vec3,
	pdf: f32,
	wi: Vec3,
) {
	if random_double() < 0.5 {
		//cook torrance
		cook_f, cook_pdf, scattered := cook_torrance_brdf_sample(material, wo, rand)
		wi = scattered

		lam_f := lambertian_eval(material.albedo)
		lam_pdf := lambertian_pdf(wi.z)

		pdf = (lam_pdf + cook_pdf) / 2

		f = cook_f + lam_f
	} else {
		///cook torrance
		lam_f, lam_pdf, scattered := lambertian_brdf_sample(material, wo, rand)
		wi = scattered

		cook_f, cook_pdf := cook_torrance_brdf_eval(
			material,
			material.roughness * material.roughness,
			wo,
			wi,
		)

		pdf = (lam_pdf + cook_pdf) / 2

		f = cook_f + lam_f
	}
	return
}

cook_torrance_brdf_sample :: proc(
	material: Material,
	wo: Vec3,
	rand: Vec2,
) -> (
	f: Vec3,
	pdf: f32,
	wi: Vec3,
) {
	alpha := material.roughness * material.roughness

	wh := cook_torrance_sample_wh(alpha, wo, rand)
	if linalg.dot(wo, wh) < 0 do return // rare
	wi = linalg.reflect(-wo, wh)
	if !same_hemisphere(wo, wi) do return

	f, pdf = cook_torrance_brdf_eval(material, alpha, wo, wi)

	return f, pdf, wi
}

cook_torrance_brdf_eval :: proc(material: Material, alpha: f32, wo, wi: Vec3) -> (Vec3, f32) {
	f0 := linalg.lerp(Vec3{0.04, 0.04, 0.04}, material.albedo, material.metallic)

	h := linalg.normalize(wo + wi)

	ndotv := max(wo.z, 0)
	ndotl := max(wi.z, 0)
	ndoth := max(h.z, 0)
	hdotv := max(linalg.dot(h, wo), 0)

	d := d(ndoth, alpha)
	g := g(ndotv, ndotl, alpha)
	f := fresnel_schlick(hdotv, f0)

	specular := (f * d * g) / (4.0 * ndotv * ndotl + 0.0001)

	//TODO: check if its the same hemisphere
	pdf := d * ndoth / (4 * hdotv + 0.0001)

	return specular, pdf
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

cook_torrance_sample_wh :: proc(alpha: f32, wo: Vec3, rand: Vec2) -> Vec3 {
	phi := (2 * math.PI) * rand.y
	theta := math.atan(alpha * math.sqrt(rand.x / (1 - rand.x)))

	cos_theta := math.cos(theta)
	sin_theta := math.sin(theta)

	w := Vec3{sin_theta * linalg.cos(phi), sin_theta * linalg.sin(phi), cos_theta}

	if !same_hemisphere(wo, w) do w = -w
	return w
}

lambertian_brdf_sample :: proc(
	material: Material,
	wo: Vec3,
	rand: Vec2,
) -> (
	f: Vec3,
	pdf: f32,
	wi: Vec3,
) {
	wi = random_cosine_direction(rand)
	if wo.z < 0 do wi.z *= -1
	pdf = lambertian_pdf(wi.z)
	f = lambertian_eval(material.albedo)
	return f, pdf, wi
}

@(private = "file")
lambertian_pdf :: proc "contextless" (ndotl: f32) -> f32 {
	return ndotl * INV_PI
}

@(private = "file")
lambertian_eval :: proc "contextless" (albedo: Vec3) -> Vec3 {
	return albedo * INV_PI
}

fresnel_schlick :: proc "contextless" (cosTheta: f32, F0: Vec3) -> Vec3 {
	return F0 + (1.0 - F0) * linalg.pow((1.0 + 0.000001) - cosTheta, 5.0)
}
