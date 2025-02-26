package raytracer

import "core:log"
import "core:math"
import glm "core:math/linalg"
_ :: log

Vec3 :: glm.Vector3f32
Mat4 :: glm.Matrix4f32

Camera :: struct {
	position: Vec3,
	forward:  Vec3,
	up:       Vec3,
	right:    Vec3,
	fov:      f32,
	aspect:   f32,
	near:     f32,
	far:      f32,
	view:     Mat4,
	proj:     Mat4,
}

camera_init :: proc(
	camera: ^Camera,
	position: Vec3 = {0, 0, -3},
	target: Vec3 = {0, 0, 0},
	up: Vec3 = {0, 1, 0},
	fov: f32 = 45,
	aspect: f32 = f32(16.0) / f32(9.0),
	near: f32 = 0.1,
	far: f32 = 100,
) {
	camera^ = {
		position = position,
		fov      = fov,
		aspect   = f32(16.0 / 9.0),
		near     = near,
		far      = far,
	}
	camera_look_at(camera, target, up)
	camera_update_matrices(camera)
}

camera_look_at :: proc(camera: ^Camera, target: Vec3, up: Vec3) {
	camera.forward = glm.normalize(target - camera.position)
	camera.right = glm.normalize(glm.cross(camera.forward, up))
	camera.up = glm.normalize(glm.cross(camera.right, camera.forward))
}

camera_update_matrices :: proc(camera: ^Camera) {
	camera.view = glm.matrix4_look_at(camera.position, camera.position + camera.forward, camera.up)
	camera.proj = glm.matrix4_perspective(
		math.to_radians(camera.fov),
		camera.aspect,
		camera.near,
		camera.far,
	)

}

camera_get_view_proj :: proc(camera: Camera) -> Mat4 {
	return camera.proj * camera.view
}
