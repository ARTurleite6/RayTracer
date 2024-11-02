package raytracer

import "core:math/linalg"

ONB :: [3]Vec3

@(require_results)
make_onb :: proc(n: Vec3) -> (axis: ONB) {
	axis[2] = linalg.normalize(n)
	a := linalg.abs(axis[2].x) > 0.9 ? Vec3{0, 1, 0} : Vec3{1, 0, 0}
	axis[1] = linalg.normalize(linalg.cross(axis[2], a))
	axis[0] = linalg.cross(axis[2], axis[1])
	return
}

@(require_results)
onb_transform :: proc(axis: ONB, v: Vec3) -> Vec3 {
	return (v.x * axis.x) + (v.y * axis.y) + (v.z * axis.z)
}
