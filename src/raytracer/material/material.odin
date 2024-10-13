package material

import "../color"

Material :: union {
	Lambertian,
	Metal,
	Dieletric,
}

Lambertian :: struct {
	albedo: color.Color,
}

Metal :: struct {
	albedo: color.Color,
	fuzz:   f64,
}

Dieletric :: struct {
	refraction_index: f64,
}
