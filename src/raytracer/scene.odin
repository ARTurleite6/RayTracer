package raytracer

import "core:slice"
import "core:log"
import "core:math"
import glm "core:math/linalg"
import "core:strings"
_ :: log

Vertex :: struct {
	pos:    Vec3,
	normal: Vec3,
	color:  Vec3,
}

Scene :: struct {
	meshes:    [dynamic]Mesh,
	objects:   [dynamic]Object,
	materials: [dynamic]Material,
}

Object :: struct {
	name:           string,
	transform:      Transform,
	mesh_index:     int,
	material_index: int,
}

Transform :: struct {
	position:     Vec3,
	rotation:     Vec3,
	scale:        Vec3,
	model_matrix: Mat4,
}

Mesh :: struct {
	name:                        string,
	vertices:                    []Vertex,
	indices:                     []u32,
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

scene_destroy :: proc(scene: ^Scene) {
	for &mesh in scene.meshes {
		mesh_destroy(&mesh)
	}

	delete(scene.meshes)
	delete(scene.objects)
	delete(scene.materials)
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
	material_index: int,
	position: Vec3 = {},
	rotation: Vec3 = {},
	scale: Vec3 = {1, 1, 1},
) -> (
	idx: int,
) {
	assert(mesh_index >= 0 && mesh_index < len(scene.meshes), "Invalid mesh index") // TODO: Move this to a error handling
	assert(material_index >= 0 && material_index < len(scene.materials), "Invalid material index") // TODO: Move this to a error handling

	transform := Transform {
		position = position,
		rotation = rotation,
		scale    = scale,
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

object_update_position :: proc(object: ^Object, new_pos: Vec3) {
	object.transform.position = new_pos
	object_update_model_matrix(object)
}

object_update_model_matrix :: proc(object: ^Object) {
	transform := &object.transform
	transform.model_matrix =
		glm.matrix4_translate(transform.position) * glm.matrix4_scale_f32(transform.scale)
}

mesh_init :: proc(mesh: ^Mesh, vertices: []Vertex, indices: []u32, name: string) -> Mesh_Error {
	mesh.name = strings.clone(name)
	mesh.vertices = slice.clone(vertices)
	mesh.indices = slice.clone(indices)

	// buffer_init_with_staging_buffer(
	// 	&mesh.vertex_buffer,
	// 	device,
	// 	raw_data(vertices),
	// 	size_of(Vertex),
	// 	len(vertices),
	// 	{
	// 		.VERTEX_BUFFER,
	// 		.SHADER_DEVICE_ADDRESS,
	// 		.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR,
	// 	},
	// ) or_return

	// if len(indices) > 0 {
	// 	buffer_init_with_staging_buffer(
	// 		&mesh.index_buffer,
	// 		device,
	// 		raw_data(indices),
	// 		size_of(u32),
	// 		len(indices),
	// 		{
	// 			.INDEX_BUFFER,
	// 			.SHADER_DEVICE_ADDRESS,
	// 			.ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR,
	// 		},
	// 	) or_return
	// }

	return nil
}

mesh_destroy :: proc(mesh: ^Mesh) {
	delete(mesh.name)
	delete(mesh.vertices)
	delete(mesh.indices)
}

create_sphere :: proc(radius: f32 = 1.0, stacks: int = 32, slices: int = 32) -> (mesh: Mesh) {
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

	mesh_init(&mesh, vertices[:], indices[:], "Sphere")
	return mesh
}


create_cube :: proc() -> (mesh: Mesh) {
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

	mesh_init(&mesh, vertices, indices, "Cube")
	return mesh
}

@(private)
create_scene :: proc() -> (scene: Scene) {
	scene_init(&scene)

	quad_mesh := create_cube()
	quad_index := scene_add_mesh(&scene, quad_mesh)

	scene_add_object(&scene, "Sphere 1", quad_index, 1, position = {1, 0, 0})
	scene_add_object(&scene, "Sphere 2", quad_index, 2, position = {-3, 0, 0})
	scene_add_object(
		&scene,
		"Ground",
		quad_index,
		0,
		position = {0, 100.9, 0}, scale = {100, 100, 100},
	)

	return scene
}