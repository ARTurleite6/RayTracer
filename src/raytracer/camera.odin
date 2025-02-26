package raytracer

import "core:log"
import "core:math"
import glm "core:math/linalg"
_ :: log

CAMERA_SPEED :: f32(5.0)

Vec3 :: glm.Vector3f32
Mat4 :: glm.Matrix4f32

Direction :: enum {
	Front,
	Backwards,
	Left,
	Right,
}

Camera :: struct {
	position, forward, up, right: Vec3,
	fov, aspect, near, far:       f32,
	view, proj:                   Mat4,
	// camera movement
	speed:                        f32,
	// mouse movement
	first_mouse:                  bool,
	last_x, last_y:               f32,
	yaw, pitch, sensivity:        f32,
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
		position    = position,
		fov         = fov,
		aspect      = f32(16.0 / 9.0),
		near        = near,
		far         = far,
		speed       = CAMERA_SPEED,
		first_mouse = false,
		yaw         = -90,
		pitch       = 0,
		sensivity   = 0.1,
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

camera_process_mouse :: proc(camera: ^Camera, x, y: f32) {
	if camera.first_mouse {
		camera.last_x = x
		camera.last_y = y
		camera.first_mouse = false
		return
	}

	offset_x := x - camera.last_x
	offset_y := camera.last_y - y

	camera.last_x = x
	camera.last_y = y

	offset_x *= camera.sensivity
	offset_y *= camera.sensivity

	camera.yaw += offset_x
	camera.pitch += offset_y

	camera.pitch = clamp(camera.pitch, -89.0, 89.0)

	// Calculate new direction
	camera.forward = {
		glm.cos(math.to_radians(camera.yaw)) * glm.cos(math.to_radians(camera.pitch)),
		glm.sin(math.to_radians(camera.pitch)),
		glm.sin(math.to_radians(camera.yaw)) * glm.cos(math.to_radians(camera.pitch)),
	}
	camera.forward = glm.normalize(camera.forward)

	// Re-calculate camera vectors
	camera.right = glm.normalize(glm.cross(camera.forward, {0, 1, 0}))
	camera.up = glm.normalize(glm.cross(camera.right, camera.forward))

	camera_update_matrices(camera)
}

camera_move :: proc(camera: ^Camera, direction: Direction, delta_time: f32) {
	movement := camera.speed * delta_time
	direction_vector: Vec3
	switch direction {
	case .Front:
		direction_vector = camera.forward
	case .Backwards:
		direction_vector = -camera.forward
	case .Right:
		direction_vector = camera.right
	case .Left:
		direction_vector = -camera.right
	}
	camera.position += direction_vector * movement

	camera_update_matrices(camera)
}

camera_get_view_proj :: proc(camera: Camera) -> Mat4 {
	return camera.proj * camera.view
}
