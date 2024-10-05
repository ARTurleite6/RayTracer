package utils

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"

Vec3 :: [3]f64

random_double :: proc(low := 0.0, upper := 1.0, generator := context.random_generator) -> f64 {
	return rand.float64_range(low, upper, generator)
}

almost_zero :: proc "contextless" (vec: Vec3) -> bool {
	epsilon := math.F64_EPSILON

	return abs(vec.x) < epsilon && abs(vec.y) < epsilon && abs(vec.z) < epsilon
}

// https://en.wikipedia.org/wiki/Schlick%27s_approximation
refletance :: proc(cosine, refraction_index: f64) -> f64 {
	r0 := (1 - refraction_index) / (1 + refraction_index)
	r0 = r0 * r0

	return r0 + (1 - r0) * math.pow(1 - cosine, 5)
}

random_unit_disk :: proc() -> Vec3 {
	for {
		p := random_vec2()
		if linalg.length2(p) < 1 {
			return p
		}
	}
}

random_unit_vector :: proc() -> Vec3 {
	for {
		p := random_vec3(-1, 1)
		lensq := linalg.length2(p)
		if 1e-160 < lensq && lensq <= 1 do return p / linalg.sqrt(lensq)
	}
}

random_vec2 :: proc(low := 0.0, upper := 1.0, generator := context.random_generator) -> Vec3 {
	context.random_generator = generator

	return {random_double(low, upper), random_double(low, upper), 0}
}

random_vec3 :: proc(low := 0.0, upper := 1.0, generator := context.random_generator) -> Vec3 {
	context.random_generator = generator

	return {random_double(low, upper), random_double(low, upper), random_double(low, upper)}
}

progress_bar :: proc(current, total: int, width: int = 50) {
	percent := f64(current) / f64(total)
	filled_width := int(f64(width) * percent)
	bar := make([]byte, width)

	for i in 0 ..< width {
		if i < filled_width {
			bar[i] = '='
		} else {
			bar[i] = ' '
		}
	}

	fmt.printf("\r[%s] %.1f%%", bar, percent * 100)

}
