package raytracer

import "core:math/linalg"

ONB :: struct {
	tangent, bitangent, normal: Vec3,
}

onb_init :: proc(space: ^ONB, normal: Vec3) {
	space.normal = linalg.normalize(normal)

	reference := linalg.abs(normal.y) > 0.99 ? Vec3{1, 0, 0} : Vec3{0, 1, 0}

	space.tangent = linalg.normalize(linalg.cross(reference, space.normal))

	space.bitangent = linalg.normalize(linalg.cross(space.normal, space.tangent))
}

@(require_results)
onb_local_to_world :: proc(space: ONB, dir: Vec3) -> Vec3 {
	return space.tangent * dir.x + space.bitangent * dir.y + space.normal * dir.z
}

@(require_results)
onb_world_to_local :: proc(space: ONB, dir: Vec3) -> Vec3 {
	return {
		linalg.dot(dir, space.tangent),
		linalg.dot(dir, space.bitangent),
		linalg.dot(dir, space.normal),
	}
}
