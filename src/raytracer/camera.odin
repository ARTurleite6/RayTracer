package raytracer

import "core:math/linalg"

Camera :: struct {
	projection, view, inverse_projection, inverse_view: Mat4,
	vertical_fov, near_clip, far_clip:                  f32,
	position, forward_direction:                        Vec3,
	ray_directions:                                     [dynamic]Vec3,
	last_mouse_position:                                Vec2,
	viewport_width, viewport_height:                    u32,
}

camera_init :: proc(camera: ^Camera, vertical_fov, near_clip, far_clip: f32) {
	camera.vertical_fov = vertical_fov
	camera.near_clip = near_clip
	camera.far_clip = far_clip

	camera.forward_direction = {0, 0, -1}
	camera.position = {0, 0, 6}
}

camera_on_resize :: proc(camera: ^Camera, width, height: u32) {
	if width == camera.viewport_width && height == camera.viewport_height {
		return
	}

	camera.viewport_width = width
	camera.viewport_height = height
}

camera_recalculate_projections :: proc(camera: ^Camera) {
	aspect := f32(camera.viewport_width) / f32(camera.viewport_height)
	camera.projection = linalg.matrix4_perspective(
		linalg.to_radians(camera.vertical_fov),
		aspect,
		camera.near_clip,
		camera.far_clip,
	)

	camera.inverse_projection = linalg.inverse(camera.projection)
}
