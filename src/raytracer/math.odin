package raytracer

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
_ :: log

SEED :: 2024

INV_PI :: 1.0 / linalg.PI

Mat4 :: linalg.Matrix4x4f32
Vec4 :: linalg.Vector4f32
Vec3 :: linalg.Vector3f32
Vec2 :: linalg.Vector2f32

@(require_results)
convert_to_rgba :: proc(color: Vec4) -> u32 {
	r := u32(color.r * 255.0)
	g := u32(color.g * 255.0)
	b := u32(color.b * 255.0)
	a := u32(color.a * 255.0)

	result: u32 = (a << 24) | (b << 16) | (g << 8) | r
	return result
}

@(require_results)
random_double :: proc(
	low: f32 = 0.0,
	upper: f32 = 1.0,
	generator := context.random_generator,
) -> f32 {
	return rand.float32_range(low, upper, generator)
}

@(require_results)
partition :: proc(s: $E/[]$T, predicate: proc(_: T) -> bool) -> uint {
	first := 0
	found := false
	for &elem, i in s {
		if !predicate(elem) {
			first = i
			found = true
			break
		}
	}
	if !found {
		return len(s) - 1
	}

	for j := first + 1; j < len(s); j += 1 {
		if (predicate(s[j])) {
			slice.swap(s, j, first)
			first += 1
		}
	}

	return uint(first)
}

@(require_results)
almost_zero :: proc "contextless" (vec: Vec3) -> bool {
	epsilon: f32 = math.F32_EPSILON

	return abs(vec.x) < epsilon && abs(vec.y) < epsilon && abs(vec.z) < epsilon
}

fresnell_reflect_ammount :: proc(n1, n2: f32, normal, incident: Vec3, reflectiviy: f32) -> f32 {
	r0 := (n1 - n2) / (n1 + n2)
	r0 *= r0
	cos_x := -linalg.dot(normal, incident)
	if n1 > n2 {
		n := n1 / n2
		sin_t2 := n * n * (1 - cos_x * cos_x)
		if sin_t2 > 1 {
			return 1
		}

		cos_x = linalg.sqrt(1.0 - sin_t2)
	}
	x := 1.0 - cos_x
	ret := r0 + (1 - r0) * x * x * x * x * x

	return reflectiviy + (1 - reflectiviy) * ret
}

// https://en.wikipedia.org/wiki/Schlick%27s_approximation
@(require_results)
refletance :: proc(cosine, refraction_index: f32) -> f32 {
	r0 := (1 - refraction_index) / (1 + refraction_index)
	r0 = r0 * r0

	return r0 + (1 - r0) * math.pow(1 - cosine, 5)
}

@(require_results)
same_hemisphere :: proc "contextless" (w: Vec3, wi: Vec3) -> bool {
	return w.z * wi.z > 0
}

@(require_results)
abs_cos_theta :: proc "contextless" (w: Vec3) -> f32 {
	return linalg.abs(w.z)
}

@(require_results)
random_cosine_direction :: proc(r: Vec2) -> (vec: Vec3) {
	r1 := r.x
	r2 := r.y

	phi := 2 * math.PI * r1

	return {
		linalg.cos(phi) * linalg.sqrt(r2),
		linalg.sin(phi) * linalg.sqrt(r2),
		linalg.sqrt(1 - r2),
	}
}

@(require_results)
random_unit_disk :: proc() -> Vec3 {
	return linalg.normalize(random_vec3(-1, 1))
}

@(require_results)
random_unit_vector :: proc() -> Vec3 {
	for {
		p := random_vec3(-1, 1)
		lensq := linalg.length2(p)
		if 1e-160 < lensq && lensq <= 1 do return p / linalg.sqrt(lensq)
	}
}

@(require_results)
random_vec2 :: proc(
	low: f32 = 0.0,
	upper: f32 = 1.0,
	generator := context.random_generator,
) -> Vec2 {
	context.random_generator = generator

	return {random_double(low, upper), random_double(low, upper)}
}

@(require_results)
random_vec3 :: proc(
	low: f32 = 0.0,
	upper: f32 = 1.0,
	generator := context.random_generator,
) -> Vec3 {
	context.random_generator = generator

	return {random_double(low, upper), random_double(low, upper), random_double(low, upper)}
}
