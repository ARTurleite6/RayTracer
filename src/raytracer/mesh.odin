package raytracer

import "core:log"
_ :: log

Mesh :: struct {
	triangles: []Triangle,
}

mesh_init :: proc(m: ^Mesh, triangles: []Triangle) {
	m.triangles = triangles
}

mesh_aabb :: proc(m: Mesh) -> AABB {
	aabb := create_empty_aabb()

	for &tr in m.triangles {
		aabb = merge_aabb(aabb, tr.box)
	}

	return aabb
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
