package raytracer

import "core:log"
_ :: log

Mesh :: struct {
	using primitive: Primitive,
	triangles:       []Triangle,
}

mesh_init :: proc(m: ^Mesh, material_index: u32, triangles: []Triangle) {
	m.triangles = triangles
	m.material_index = material_index

	m.box = create_empty_aabb()
	for &t in m.triangles {
		m.box = merge_aabb(m.box, t.box)
	}

}

mesh_hit :: proc(
	mesh: Mesh,
	ray: Ray,
	interval: Interval,
) -> (
	distance: f32,
	normal: Vec3,
	did_hit: bool,
) {
	if !aabb_hit(mesh.box, ray, interval) {
		return
	}

	index: int
	if distance, index, normal, did_hit = hit(mesh.triangles, ray, interval); did_hit {
		return distance, normal, did_hit
	}

	return -1, {}, false
}

mesh_destroy :: proc(m: ^Mesh) {
	delete(m.triangles)
	m.triangles = nil
}
