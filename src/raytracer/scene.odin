package raytracer

import glm "core:math/linalg"
// import vma "external:odin-vma"
import vk "vendor:vulkan"

Vertex :: struct {
	pos:   Vec3,
	color: Vec3,
}

VERTEX_INPUT_BINDING_DESCRIPTION := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Vertex),
	inputRate = .VERTEX,
}

VERTEX_INPUT_ATTRIBUTE_DESCRIPTION := [?]vk.VertexInputAttributeDescription {
	{binding = 0, location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Vertex, pos))},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = u32(offset_of(Vertex, color)),
	},
}

Scene :: struct {
	meshes:          [dynamic]Mesh,
	objects:         [dynamic]Object,
	instance_buffer: Buffer,
	rt_builder:      Raytracing_Builder,
}

Object :: struct {
	name:       string,
	transform:  Transform,
	mesh_index: int,
}

Transform :: struct {
	position:     Vec3,
	rotation:     Vec3,
	scale:        Vec3,
	model_matrix: Mat4,
}

Mesh :: struct {
	name:          string,
	vertex_count:  u32,
	index_count:   u32,
	vertex_buffer: Buffer,
	index_buffer:  Buffer,
}

Mesh_Error :: union {
	Buffer_Error,
}

Scene_UBO :: struct {
	view:       Mat4,
	projection: Mat4,
}

Push_Constants :: struct {
	model_matrix: Mat4,
}

scene_init :: proc(scene: ^Scene, allocator := context.allocator) {
	scene.meshes = make([dynamic]Mesh, allocator)
	scene.objects = make([dynamic]Object, allocator)
}

scene_destroy :: proc(scene: ^Scene, device: ^Device) {
	for &mesh in scene.meshes {
		mesh_destroy(&mesh, device)
	}
	delete(scene.meshes)
	delete(scene.objects)
	// delete(scene.bottom_level_as)
	scene^ = {}
}

scene_add_mesh :: proc(scene: ^Scene, mesh: Mesh) -> int {
	append(&scene.meshes, mesh)
	return len(scene.meshes) - 1
}

scene_add_object :: proc(
	scene: ^Scene,
	name: string,
	mesh_index: int,
	transform: Transform,
) -> (
	idx: int,
) {
	assert(mesh_index >= 0 && mesh_index < len(scene.meshes), "Invalid mesh index") // TODO: Move this to a error handling

	object := Object {
		name       = name,
		transform  = transform,
		mesh_index = mesh_index,
	}
	object_update_model_matrix(&object)

	append(&scene.objects, object)
	return len(scene.objects) - 1
}

scene_create_as :: proc(scene: ^Scene, device: ^Device) {
	create_bottom_level_as(&scene.rt_builder, scene^, device)
	create_top_level_as(&scene.rt_builder, scene^, device)
}

// TODO: probably in the future would it be nice to change this, to not pass the pipeline_layout
scene_draw :: proc(scene: ^Scene, cmd: vk.CommandBuffer, pipeline_layout: vk.PipelineLayout) {
	for &object in scene.objects {

		transform := object.transform.model_matrix // glm.MATRIX4F32_IDENTITY
		// glm.matrix4_rotate_f32(90 * glm.DEG_PER_RAD, {0, 1, 0}) *
		// glm.matrix4_rotate_f32(90 * glm.DEG_PER_RAD, {0, 0, 1})

		push_constant := Push_Constants {
			model_matrix = transform,
		}

		vk.CmdPushConstants(
			cmd,
			pipeline_layout,
			{.VERTEX},
			0,
			size_of(Push_Constants),
			&push_constant,
		)

		mesh := &scene.meshes[object.mesh_index]

		mesh_draw(mesh, cmd)
	}
}

object_update_position :: proc(object: ^Object, new_pos: Vec3) {
	object.transform.position = new_pos
	object_update_model_matrix(object)
}

object_update_model_matrix :: proc(object: ^Object) {
	transform := &object.transform
	transform.model_matrix = glm.matrix4_translate(transform.position)
}

@(private)
create_scene :: proc(device: ^Device) -> (scene: Scene) {
	scene_init(&scene)

	quad_mesh := create_cube(device)
	mesh_index := scene_add_mesh(&scene, quad_mesh)

	scene_add_object(&scene, "quad", mesh_index, {})

	return scene
}

mesh_init :: proc(
	mesh: ^Mesh,
	device: ^Device,
	vertices: []Vertex,
	indices: []u32,
	name: string,
) -> Mesh_Error {
	mesh.name = name
	mesh.vertex_count = u32(len(vertices))

	vertex_buffer_init(&mesh.vertex_buffer, device, vertices) or_return
	if len(indices) > 0 {
		buffer_init_with_staging_buffer(
			&mesh.index_buffer,
			device,
			raw_data(indices),
			size_of(u32),
			len(indices),
			{
				.INDEX_BUFFER,
				.SHADER_DEVICE_ADDRESS,
				.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR,
			},
		) or_return
		mesh.index_count = u32(len(indices))
	}

	return nil
}

mesh_destroy :: proc(mesh: ^Mesh, device: ^Device) {
	buffer_destroy(&mesh.vertex_buffer, device)
}

mesh_draw :: proc(mesh: ^Mesh, cmd: vk.CommandBuffer) {
	offsets := vk.DeviceSize(0)
	vk.CmdBindVertexBuffers(cmd, 0, 1, &mesh.vertex_buffer.handle, &offsets)

	if mesh.index_count > 0 {
		vk.CmdBindIndexBuffer(cmd, mesh.index_buffer.handle, 0, .UINT32)
		vk.CmdDrawIndexed(cmd, mesh.index_count, 1, 0, 0, 0)
	} else {
		vk.CmdDraw(cmd, mesh.vertex_count, 1, 0, 0)
	}
}

create_quad :: proc(device: ^Device) -> (mesh: Mesh) {

	vertices := []Vertex {
		{{-0.5, -0.5, 0}, {1, 0, 0}}, // Bottom-left
		{{-0.5, 0.5, 0}, {1, 1, 1}}, // Top-left
		{{0.5, 0.5, 0}, {0, 0, 1}}, // Top-right
		{{0.5, -0.5, 0}, {0, 1, 0}}, // Bottom-right
	}

	// Counter-clockwise indices
	indices := []u32 {
		0,
		1,
		2, // First triangle (left side)
		0,
		2,
		3, // Second triangle (right side)
	}
	mesh_init(&mesh, device, vertices, indices, "Quad")

	return mesh
}

create_cube :: proc(device: ^Device) -> (mesh: Mesh) {
	vertices := []Vertex {
		// Front face
		{{-0.5, -0.5, 0.5}, {1, 0, 0}}, // 0
		{{-0.5, 0.5, 0.5}, {1, 1, 0}}, // 1
		{{0.5, 0.5, 0.5}, {0, 0, 1}}, // 2
		{{0.5, -0.5, 0.5}, {0, 1, 0}}, // 3

		// Back face
		{{-0.5, -0.5, -0.5}, {1, 0, 1}}, // 4
		{{-0.5, 0.5, -0.5}, {0, 0, 0}}, // 5
		{{0.5, 0.5, -0.5}, {1, 1, 1}}, // 6
		{{0.5, -0.5, -0.5}, {0, 1, 1}}, // 7
	}

	// Counter-clockwise indices for each face
	indices := []u32 {
		// Front face
		0,
		1,
		2,
		0,
		2,
		3,

		// Back face
		7,
		6,
		5,
		7,
		5,
		4,

		// Right face
		3,
		2,
		6,
		3,
		6,
		7,

		// Left face
		4,
		5,
		1,
		4,
		1,
		0,

		// Top face
		1,
		5,
		6,
		1,
		6,
		2,

		// Bottom face
		4,
		0,
		3,
		4,
		3,
		7,
	}

	mesh_init(&mesh, device, vertices, indices, "Cube")
	return mesh
}
