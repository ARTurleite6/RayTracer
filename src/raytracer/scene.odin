package raytracer

import "core:math"
import glm "core:math/linalg"
// import vma "external:odin-vma"
import "core:log"
import vk "vendor:vulkan"

_ :: log

Vertex :: struct {
	pos:    Vec3,
	normal: Vec3,
	color:  Vec3,
}

Scene :: struct {
	meshes:             [dynamic]Mesh,
	objects:            [dynamic]Object,
	materials:          [dynamic]Material,

	// GPU buffers
	object_data_buffer: Buffer,
	material_buffer:    Buffer,
	instance_buffer:    Buffer,
	rt_builder:         Raytracing_Builder,
}

Object :: struct {
	name:           string,
	transform:      Transform,
	mesh_index:     int,
	material_index: int,
}

Object_Data :: struct {
	vertex_buffer_address, index_buffer_address: vk.DeviceAddress,
	material_index:                              u32,
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

Material :: struct {
	name:           string,
	albedo:         Vec3,
	emission_color: Vec3,
	emission_power: f32,
}

Scene_UBO :: struct {
	view:       Mat4,
	projection: Mat4,
}

Graphics_Push_Constant :: struct {
	model_matrix: Mat4,
}

Raytracing_Push_Constant :: struct {
	clear_color:        Vec3,
	light_intensity:    f32,
	light_pos:          Vec3,
	ambient_strength:   f32,
	accumulation_frame: u32,
}

scene_init :: proc(scene: ^Scene, allocator := context.allocator) {
	scene.meshes = make([dynamic]Mesh, allocator)
	scene.objects = make([dynamic]Object, allocator)
	scene.materials = make([dynamic]Material, allocator)

	append(
		&scene.materials,
		Material{name = "green", albedo = {0.0, 1.0, 0.0}},
		Material{name = "red", albedo = {1.0, 0.0, 0.0}},
		Material {
			name = "sun",
			albedo = {0.1, 0.1, 0.1},
			emission_color = {1, 1, 0},
			emission_power = 5.0,
		},
	)
}

scene_destroy :: proc(scene: ^Scene, device: ^Device) {
	// for as in scene.rt_builder.as {
	// }
	delete(scene.rt_builder.as)

	for &mesh in scene.meshes {
		mesh_destroy(&mesh, device)
	}

	buffer_destroy(&scene.material_buffer, device)
	delete(scene.meshes)
	delete(scene.objects)
	delete(scene.materials)
	scene^ = {}
}

scene_create_buffers :: proc(scene: ^Scene, device: ^Device) -> (err: Buffer_Error) {
	scene_create_material_buffers(scene, device) or_return
	return scene_create_object_data_buffers(scene, device)
}

scene_update_descriptor_writes :: proc(scene: Scene, descriptor_manager: ^Descriptor_Set_Manager) {
	descriptor_manager_write_buffer(
		descriptor_manager,
		"scene_data",
		0,
		0,
		scene.material_buffer.handle,
		vk.DeviceSize(vk.WHOLE_SIZE),
	)

	// Update object data buffer binding
	descriptor_manager_write_buffer(
		descriptor_manager,
		"scene_data",
		0,
		1,
		scene.object_data_buffer.handle,
		vk.DeviceSize(vk.WHOLE_SIZE),
	)
}

scene_update_material :: proc(
	scene: ^Scene,
	material_index: int,
	device: ^Device,
	descriptor_manager: ^Descriptor_Set_Manager = nil,
) -> (
	err: Buffer_Error,
) {
	assert(
		material_index >= 0 && material_index <= len(scene.materials),
		"material index not valid",
	)
	buffer_destroy(&scene.material_buffer, device)

	scene_create_material_buffers(scene, device) or_return

	if descriptor_manager != nil {
		descriptor_manager_write_buffer(
			descriptor_manager,
			"scene_data",
			0, // set index
			0, // binding index for materials
			scene.material_buffer.handle,
			vk.DeviceSize(vk.WHOLE_SIZE),
		)
	}
	return .None
}

scene_create_material_buffers :: proc(scene: ^Scene, device: ^Device) -> (err: Buffer_Error) {
	Material_Data :: struct {
		albedo:         Vec3,
		emission_color: Vec3,
		emission_power: f32,
	}
	materials := make([]Material_Data, len(scene.materials), context.temp_allocator)

	for mat, i in scene.materials {
		materials[i].albedo = mat.albedo
		materials[i].emission_color = mat.emission_color
		materials[i].emission_power = mat.emission_power
	}

	buffer_init_with_staging_buffer(
		&scene.material_buffer,
		device,
		raw_data(materials),
		size_of(Material_Data),
		len(materials),
		{.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
	) or_return
	return .None
}

scene_create_object_data_buffers :: proc(scene: ^Scene, device: ^Device) -> (err: Buffer_Error) {
	objects := make([]Object_Data, len(scene.objects), context.temp_allocator)
	for obj, i in scene.objects {
		mesh := &scene.meshes[obj.mesh_index]
		objects[i] = {
			material_index        = u32(obj.material_index),
			vertex_buffer_address = buffer_get_device_address(mesh.vertex_buffer, device^),
			index_buffer_address  = buffer_get_device_address(mesh.index_buffer, device^),
		}
	}

	buffer_init_with_staging_buffer(
		&scene.object_data_buffer,
		device,
		raw_data(objects),
		size_of(Object_Data),
		len(objects),
		{.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
	) or_return

	return .None
}

scene_add_mesh :: proc(scene: ^Scene, mesh: Mesh) -> int {
	append(&scene.meshes, mesh)
	return len(scene.meshes) - 1
}

scene_add_object :: proc(
	scene: ^Scene,
	name: string,
	mesh_index: int,
	material_index: int,
	transform: Transform,
) -> (
	idx: int,
) {
	assert(mesh_index >= 0 && mesh_index < len(scene.meshes), "Invalid mesh index") // TODO: Move this to a error handling

	transform := transform
	if transform.scale == {} {
		transform.scale = {1, 1, 1}
	}

	object := Object {
		name           = name,
		transform      = transform,
		mesh_index     = mesh_index,
		material_index = material_index,
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

		push_constant := Graphics_Push_Constant {
			model_matrix = transform,
		}

		vk.CmdPushConstants(
			cmd,
			pipeline_layout,
			{.VERTEX},
			0,
			size_of(Graphics_Push_Constant),
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
	transform.model_matrix =
		glm.matrix4_translate(transform.position) * glm.matrix4_scale_f32(transform.scale)
}

@(private)
create_scene :: proc(device: ^Device) -> (scene: Scene) {
	scene_init(&scene)

	quad_mesh := create_cube(device)
	sphere_mesh := create_sphere(device, radius = 1)
	_ = scene_add_mesh(&scene, quad_mesh)
	sphere_index := scene_add_mesh(&scene, sphere_mesh)

	scene_add_object(&scene, "Sphere 1", sphere_index, 1, {position = {1, 0, 0}})
	scene_add_object(&scene, "Sphere 2", sphere_index, 2, Transform{position = {-3, 0, 0}})
	scene_add_object(
		&scene,
		"Ground",
		sphere_index,
		0,
		Transform{position = {0, 100.9, 0}, scale = {100, 100, 100}},
	)

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

create_sphere :: proc(
	device: ^Device,
	radius: f32 = 1.0,
	stacks: int = 32,
	slices: int = 32,
) -> (
	mesh: Mesh,
) {
	vertex_count := (stacks + 1) * (slices + 1)
	index_count := stacks * slices * 6

	vertices := make([dynamic]Vertex, 0, vertex_count, context.temp_allocator)
	indices := make([dynamic]u32, 0, index_count, context.temp_allocator)


	// Generate vertices
	for i := 0; i <= stacks; i += 1 {
		phi := math.PI * f32(i) / f32(stacks) // Vertical angle
		sin_phi := math.sin(phi)
		cos_phi := math.cos(phi)

		for j := 0; j <= slices; j += 1 {
			theta := 2.0 * math.PI * f32(j) / f32(slices) // Horizontal angle
			sin_theta := math.sin(theta)
			cos_theta := math.cos(theta)

			// Calculate vertex position
			pos := Vec3 {
				radius * sin_phi * cos_theta, // x
				radius * cos_phi, // y
				radius * sin_phi * sin_theta, // z
			}

			normal := glm.vector_normalize(pos)

			// Calculate vertex color (can be modified as needed)
			// Here we're using normalized position as color
			color := Vec3 {
				(pos.x / radius + 1.0) * 0.5,
				(pos.y / radius + 1.0) * 0.5,
				(pos.z / radius + 1.0) * 0.5,
			}

			append(&vertices, Vertex{pos = pos, normal = normal, color = color})
		}
	}

	// Generate indices
	for i := 0; i < stacks; i += 1 {
		for j := 0; j < slices; j += 1 {
			// Calculate the indices of the quad's vertices
			top_left := u32(i * (slices + 1) + j)
			top_right := u32(i * (slices + 1) + j + 1)
			bottom_left := u32((i + 1) * (slices + 1) + j)
			bottom_right := u32((i + 1) * (slices + 1) + j + 1)

			// First triangle of the quad
			append(&indices, top_left)
			append(&indices, bottom_left)
			append(&indices, top_right)

			// Second triangle of the quad
			append(&indices, top_right)
			append(&indices, bottom_left)
			append(&indices, bottom_right)
		}
	}

	mesh_init(&mesh, device, vertices[:], indices[:], "Sphere")
	return mesh
}

create_cube :: proc(device: ^Device) -> (mesh: Mesh) {
	vertices := []Vertex {
		// Front face (normal: 0, 0, 1)
		{{-0.5, -0.5, 0.5}, {0, 0, 1}, {1, 0, 0}}, // 0
		{{-0.5, 0.5, 0.5}, {0, 0, 1}, {1, 1, 0}}, // 1
		{{0.5, 0.5, 0.5}, {0, 0, 1}, {0, 0, 1}}, // 2
		{{0.5, -0.5, 0.5}, {0, 0, 1}, {0, 1, 0}}, // 3

		// Back face (normal: 0, 0, -1)
		{{-0.5, -0.5, -0.5}, {0, 0, -1}, {1, 0, 1}}, // 4
		{{-0.5, 0.5, -0.5}, {0, 0, -1}, {0, 0, 0}}, // 5
		{{0.5, 0.5, -0.5}, {0, 0, -1}, {1, 1, 1}}, // 6
		{{0.5, -0.5, -0.5}, {0, 0, -1}, {0, 1, 1}}, // 7

		// Right face (normal: 1, 0, 0)
		{{0.5, -0.5, 0.5}, {1, 0, 0}, {0, 1, 0}}, // 8
		{{0.5, 0.5, 0.5}, {1, 0, 0}, {0, 0, 1}}, // 9
		{{0.5, 0.5, -0.5}, {1, 0, 0}, {1, 1, 1}}, // 10
		{{0.5, -0.5, -0.5}, {1, 0, 0}, {0, 1, 1}}, // 11

		// Left face (normal: -1, 0, 0)
		{{-0.5, -0.5, -0.5}, {-1, 0, 0}, {1, 0, 1}}, // 12
		{{-0.5, 0.5, -0.5}, {-1, 0, 0}, {0, 0, 0}}, // 13
		{{-0.5, 0.5, 0.5}, {-1, 0, 0}, {1, 1, 0}}, // 14
		{{-0.5, -0.5, 0.5}, {-1, 0, 0}, {1, 0, 0}}, // 15

		// Top face (normal: 0, 1, 0)
		{{-0.5, 0.5, 0.5}, {0, 1, 0}, {1, 1, 0}}, // 16
		{{-0.5, 0.5, -0.5}, {0, 1, 0}, {0, 0, 0}}, // 17
		{{0.5, 0.5, -0.5}, {0, 1, 0}, {1, 1, 1}}, // 18
		{{0.5, 0.5, 0.5}, {0, 1, 0}, {0, 0, 1}}, // 19

		// Bottom face (normal: 0, -1, 0)
		{{-0.5, -0.5, -0.5}, {0, -1, 0}, {1, 0, 1}}, // 20
		{{-0.5, -0.5, 0.5}, {0, -1, 0}, {1, 0, 0}}, // 21
		{{0.5, -0.5, 0.5}, {0, -1, 0}, {0, 1, 0}}, // 22
		{{0.5, -0.5, -0.5}, {0, -1, 0}, {0, 1, 1}}, // 23
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
