package raytracer

import "core:log"
import "core:math/linalg"
_ :: log

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

	camera_recalculate_projections(camera)
	camera_recalculate_view(camera)
	camera_recalculate_ray_directions(camera)
}

camera_recalculate_view :: proc(camera: ^Camera) {
	camera.view = linalg.matrix4_look_at(
		camera.position,
		camera.position + camera.forward_direction,
		Vec3{0, 1, 0},
	)
	camera.inverse_view = linalg.inverse(camera.view)
}

camera_on_resize :: proc(camera: ^Camera, width, height: u32) {
	if width == camera.viewport_width && height == camera.viewport_height {
		return
	}

	log.debugf(
		"Resizing camera on from (%d, %d) to (%d, %d)",
		camera.viewport_width,
		camera.viewport_height,
		width,
		height,
	)

	camera.viewport_width = width
	camera.viewport_height = height

	camera_recalculate_projections(camera)
	camera_recalculate_ray_directions(camera)
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

camera_recalculate_ray_directions :: proc(camera: ^Camera) {
	resize(&camera.ray_directions, camera.viewport_width * camera.viewport_height)

	for y in 0 ..< camera.viewport_height {
		for x in 0 ..< camera.viewport_width {
			coord := Vec2 {
				f32(x) / f32(camera.viewport_width),
				f32(y) / f32(camera.viewport_height),
			}
			coord = coord * 2 - 1

			target := camera.inverse_projection * Vec4{coord.x, coord.y, 1, 1}
			target_normalized := linalg.normalize(target.xyz / target.w)
			ray_direction :=
				(camera.inverse_view * Vec4{target_normalized.x, target_normalized.y, target_normalized.z, 0}).xyz
			camera.ray_directions[x + y * camera.viewport_width] = ray_direction
		}
	}
}
