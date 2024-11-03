package raytracer

Material :: struct {
	albedo:                              Vec3,
	roughness, metallic, emission_power: f32,
	emission_color:                      Vec3,
}

material_init :: proc(
	material: ^Material,
	albedo: Vec3,
	index_of_refraction: f32 = 1,
	roughness: f32 = 1.0,
	metallic: f32 = 0.0,
	emission_power: f32 = 0.0,
	emission_color := Vec3{},
	refractive := false,
	refraction_index: f32 = -1.0,
) {
	material.albedo = albedo
	material.roughness = roughness
	material.metallic = metallic
	material.emission_power = emission_power
	material.emission_color = emission_color
}

material_get_emission :: proc(material: Material) -> Vec3 {
	return material.emission_color * material.emission_power
}
