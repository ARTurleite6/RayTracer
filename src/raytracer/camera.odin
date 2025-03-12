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
	ubo_buffers:                            [MAX_FRAMES_IN_FLIGHT]Buffer,
	descriptor_set_layout:                  vk.DescriptorSetLayout,
	descriptor_sets:                        [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
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

	for &b in camera.ubo_buffers {
		buffer_init(&b, camera.device, size_of(Scene_UBO), 1, {.UNIFORM_BUFFER}, .Gpu_To_Cpu)
		buffer_map(&b, camera.device)
	}
	binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorType  = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags      = {.VERTEX, .FRAGMENT, .RAYGEN_KHR},
	}

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &binding,
	}

	vk.CreateDescriptorSetLayout(
		device.logical_device.ptr,
		&create_info,
		nil,
		&camera.descriptor_set_layout,
	)

	layouts := [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout{}
	for &layout in layouts {
		layout = camera.descriptor_set_layout
	}

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = descriptor_pool,
		descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
		pSetLayouts        = raw_data(layouts[:]),
	}

	vk.AllocateDescriptorSets(
		camera.device.logical_device.ptr,
		&alloc_info,
		raw_data(camera.descriptor_sets[:]),
	)

	for _, i in camera.ubo_buffers {
		buffer_info := vk.DescriptorBufferInfo {
			buffer = camera.ubo_buffers[i].handle,
			offset = 0,
			range  = size_of(Scene_UBO),
		}

		write := vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = camera.descriptor_sets[i],
			dstBinding      = 0,
			dstArrayElement = 0,
			descriptorType  = .UNIFORM_BUFFER,
			descriptorCount = 1,
			pBufferInfo     = &buffer_info,
		}

		vk.UpdateDescriptorSets(device.logical_device.ptr, 1, &write, 0, nil)
	}
}

camera_look_at :: proc(camera: ^Camera, target: Vec3, up: Vec3) {
	camera.forward = glm.normalize(target - camera.position)
	camera.right = glm.cross(camera.forward, camera.up)
}

camera_update_buffers :: proc(camera: ^Camera, current_frame: int) {
	ubo_data := Scene_UBO {
		view       = camera.view,
		projection = camera.proj,
	}

	data := &ubo_data
	buffer := &camera.ubo_buffers[current_frame]
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
