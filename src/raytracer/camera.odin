package raytracer

import "core:log"
import "core:math"
import glm "core:math/linalg"
import vk "vendor:vulkan"
_ :: log

CAMERA_SPEED :: f32(5.0)
CAMERA_SENSIVITY :: f32(0.001)


Vec2 :: glm.Vector2f32
Vec3 :: glm.Vector3f32
Vec4 :: glm.Vector4f32
Mat4 :: glm.Matrix4f32

Camera_UBO :: struct {
	projection:         Mat4,
	view:               Mat4,
	inverse_view:       Mat4,
	inverse_projection: Mat4,
}

Direction :: enum {
	Front,
	Backwards,
	Left,
	Right,
	Up,
	Down,
}

Camera :: struct {
	position, forward, up, right:           Vec3,
	fov, aspect, near, far:                 f32,
	view, proj, inverse_proj, inverse_view: Mat4,
	// camera movement
	speed:                                  f32,
	// mouse movement
	last_mouse_position:                    Vec2,
	sensivity:                              f32,

	// vulkan resources
	ubo_buffer:                             Buffer,
	descriptor_set_layout:                  vk.DescriptorSetLayout,
	descriptor_sets:                        vk.DescriptorSet,
	device:                                 ^Device,
}

camera_init :: proc(
	camera: ^Camera,
	position: Vec3,
	aspect: f32,
	device: ^Device,
	descriptor_pool: vk.DescriptorPool,
	target: Vec3 = {0, 0, 0},
	up: Vec3 = {0, 1, 0},
	fov: f32 = 45,
	near: f32 = 0.1,
	far: f32 = 100,
) {
	camera^ = {
		position  = position,
		fov       = fov,
		up        = up,
		aspect    = aspect,
		near      = near,
		far       = far,
		speed     = CAMERA_SPEED,
		sensivity = CAMERA_SENSIVITY,
		device    = device,
	}
	camera_look_at(camera, target, up)
	camera_update_matrices(camera)

	buffer_init(
		&camera.ubo_buffer,
		camera.device,
		size_of(Camera_UBO),
		1,
		{.UNIFORM_BUFFER},
		.Gpu_To_Cpu,
	)
	buffer_map(&camera.ubo_buffer, camera.device)
	camera.descriptor_set_layout, _ = create_descriptor_set_layout(
		{
			{
				binding = 0,
				descriptorType = .UNIFORM_BUFFER,
				descriptorCount = 1,
				stageFlags = {.VERTEX, .FRAGMENT, .RAYGEN_KHR},
			},
		},
		device.logical_device.ptr,
	)


	camera.descriptor_sets, _ = allocate_single_descriptor_set(
		descriptor_pool,
		&camera.descriptor_set_layout,
		device.logical_device.ptr,
	)

	buffer_info := vk.DescriptorBufferInfo {
		buffer = camera.ubo_buffer.handle,
		offset = 0,
		range  = size_of(Camera_UBO),
	}

	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = camera.descriptor_sets,
		dstBinding      = 0,
		dstArrayElement = 0,
		descriptorType  = .UNIFORM_BUFFER,
		descriptorCount = 1,
		pBufferInfo     = &buffer_info,
	}

	vk.UpdateDescriptorSets(device.logical_device.ptr, 1, &write, 0, nil)
}

camera_destroy :: proc(camera: ^Camera) {
	buffer_destroy(&camera.ubo_buffer, camera.device)
	descriptor_set_layout_destroy(camera.descriptor_set_layout, camera.device.logical_device.ptr)

	camera^ = {}
}

camera_look_at :: proc(camera: ^Camera, target: Vec3, up: Vec3) {
	camera.forward = glm.normalize(target - camera.position)
	camera.right = glm.cross(camera.forward, camera.up)
}

camera_update_buffers :: proc(camera: ^Camera) {
	ubo_data := Camera_UBO {
		projection         = camera.proj,
		view               = camera.view,
		inverse_view       = camera.inverse_view,
		inverse_projection = camera.inverse_proj,
	}

	data := &ubo_data
	buffer := &camera.ubo_buffer
	buffer_write(buffer, data)
	buffer_flush(buffer, camera.device^)
}

camera_update_aspect_ratio :: proc(camera: ^Camera, aspect_ratio: f32) {
	camera.aspect = aspect_ratio
	camera_update_matrices(camera)
}

camera_update_matrices :: proc(camera: ^Camera) {
	camera.view = glm.matrix4_look_at(camera.position, camera.position + camera.forward, camera.up)
	camera.proj = glm.matrix4_perspective(
		math.to_radians(camera.fov),
		camera.aspect,
		camera.near,
		camera.far,
	)
	camera.inverse_view = glm.matrix4_inverse_f32(camera.view)
	camera.inverse_proj = glm.matrix4_inverse_f32(camera.proj)
}

camera_process_mouse :: proc(camera: ^Camera, x, y: f32, move: bool) {
	current_pos := Vec2{x, y}

	delta := current_pos - camera.last_mouse_position
	camera.last_mouse_position = current_pos

	if !move || delta == {} do return

	pitch_delta := delta.y * camera.sensivity
	yaw_delta := delta.x * camera.sensivity

	rotation := glm.normalize(
		glm.cross(
			glm.quaternion_angle_axis_f32(pitch_delta, camera.right),
			glm.quaternion_angle_axis_f32(-yaw_delta, {0, 1, 0}),
		),
	)

	camera.forward = glm.quaternion_mul_vector3(rotation, camera.forward)
	camera.right = glm.cross(camera.forward, camera.up)

	camera_update_matrices(camera)
}

camera_move :: proc(camera: ^Camera, direction: Direction, delta_time: f32) {
	movement := camera.speed * delta_time

	direction_vector: Vec3
	switch direction {
	case .Up:
		direction_vector = -camera.up
	case .Down:
		direction_vector = camera.up
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
