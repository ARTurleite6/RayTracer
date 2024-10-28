package raytracer

Material :: struct {
	albedo:                              Vec3,
	roughness, metallic, emission_power: f32,
	emission_color:                      Vec3,
}

material_get_emission :: proc(material: Material) -> Vec3 {
	return material.emission_color * material.emission_power
}
