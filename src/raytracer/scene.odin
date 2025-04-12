package raytracer

import "core:log"
import "core:math"
import glm "core:math/linalg"
import "core:slice"
import "core:strings"
_ :: log

Vertex :: struct {
	pos:    Vec3,
	normal: Vec3,
	color:  Vec3,
}

Scene :: struct {
	meshes:          [dynamic]Mesh,
	objects:         [dynamic]Object,
	materials:       [dynamic]Material,

	// state tracking
	// TODO: I need to see this better in the future
	dirty_materials: map[int]bool,
	dirty_objects:   map[int]bool,
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
	name:     string,
	vertices: []Vertex,
	indices:  []u32,
}

Mesh_Error :: union {
	Buffer_Error,
}

Material :: struct {
	name:                                                   string,
	albedo, emission_color:                                 Vec3,
	emission_power, roughness, metallic, transmission, ior: f32,
}

scene_init :: proc(scene: ^Scene) {
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

scene_add_material :: proc(scene: ^Scene, material: Material) {
	append(&scene.materials, material)
}

scene_delete_material :: proc(scene: ^Scene, material_index: int) {
	material := scene.materials[material_index]
	delete(material.name)
	unordered_remove(&scene.materials, material_index)

	for _, i in scene.objects {
		scene_update_object_material(scene, i, 0)
	}
}

scene_update_material :: proc(scene: ^Scene, material_idx: int, material: Material) {
	scene.materials[material_idx] = material
	scene.dirty_materials[material_idx] = true
}

scene_update_object_material :: proc(scene: ^Scene, object_idx: int, new_material_idx: int) {
	scene.objects[object_idx].material_index = new_material_idx
	scene.dirty_objects[object_idx] = true
}

scene_add_mesh :: proc(scene: ^Scene, mesh: Mesh) -> int {
	append(&scene.meshes, mesh)
	return len(scene.meshes) - 1
}

scene_update_object_position :: proc(scene: ^Scene, object_index: int, new_position: Vec3) {
	object := &scene.objects[object_index]
	object_update_position(object, new_position)

	scene.dirty_objects[object_index] = true
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
	return nil
}

mesh_destroy :: proc(mesh: ^Mesh) {
	delete(mesh.name)
	delete(mesh.vertices)
	delete(mesh.indices)
}

create_sphere :: proc(stacks: int = 32, slices: int = 32) -> (mesh: Mesh) {
	vertex_count := (stacks + 1) * (slices + 1)
	index_count := stacks * slices * 6
	radius: f32 = 1

	vertices := make([dynamic]Vertex, 0, vertex_count, context.temp_allocator)
	indices := make([dynamic]u32, 0, index_count, context.temp_allocator)


	// Generate vertices with improved distribution
	for i := 0; i <= stacks; i += 1 {
		// Use a non-linear distribution for phi to reduce pole bunching
		// This makes more even triangles across the sphere
		phi := math.PI * f32(i) / f32(stacks)

		sin_phi := math.sin(phi)
		cos_phi := math.cos(phi)

		for j := 0; j <= slices; j += 1 {
			theta := 2.0 * math.PI * f32(j) / f32(slices)
			sin_theta := math.sin(theta)
			cos_theta := math.cos(theta)

			// Calculate vertex position
			pos := Vec3 {
				radius * sin_phi * cos_theta,
				radius * cos_phi,
				radius * sin_phi * sin_theta,
			}

			// This is the key - make sure normals are EXACTLY normalized
			normal := glm.vector_normalize(pos)

			// Use interpolation scheme for colors if desired
			color := Vec3{(normal.x + 1.0) * 0.5, (normal.y + 1.0) * 0.5, (normal.z + 1.0) * 0.5}

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

	indices := []u32 {
		// Front face
		0,
		1,
		2,
		0,
		2,
		3,

		// Back face
		4,
		5,
		6,
		4,
		6,
		7,

		// Right face
		8,
		9,
		10,
		8,
		10,
		11,

		// Left face
		12,
		13,
		14,
		12,
		14,
		15,

		// Top face
		16,
		17,
		18,
		16,
		18,
		19,

		// Bottom face
		20,
		21,
		22,
		20,
		22,
		23,
	}

	mesh_init(&mesh, vertices, indices, "Cube")

	mesh_init(&mesh, vertices, indices, "Cube")
	return mesh
}

@(private)
create_scene :: proc() -> (scene: Scene) {
	return create_cornell_box()
	// scene_init(&scene)

	// sphere_index := scene_add_mesh(&scene, create_sphere(stacks = 100, slices = 100))

	// scene_add_object(&scene, "Sphere 1", sphere_index, 1, position = {8.0, 1, 0})
	// scene_add_object(&scene, "Sphere 2", sphere_index, 2, position = {0, 0, 0})
	// scene_add_object(&scene, "Ground", sphere_index, 0, position = {2.5, 0, 0})

	// return scene
}

@(private)
create_cornell_box :: proc() -> (scene: Scene) {
	scene_init(&scene)

	white_material_idx := len(scene.materials)
	scene_add_material(
		&scene,
		Material{name = "white", albedo = {0.73, 0.73, 0.73}, roughness = 1.0},
	)

	red_material_idx := len(scene.materials)
	scene_add_material(
		&scene,
		Material{name = "red", albedo = {0.65, 0.05, 0.05}, roughness = 1.0},
	)

	green_material_idx := len(scene.materials)
	scene_add_material(
		&scene,
		Material{name = "green", albedo = {0.12, 0.45, 0.15}, roughness = 1.0},
	)

	light_material_idx := len(scene.materials)
	scene_add_material(
		&scene,
		Material {
			name = "light",
			albedo = {0.8, 0.8, 0.8},
			emission_color = {1.0, 1.0, 1.0},
			emission_power = 15.0,
		},
	)

	// Create a cube mesh for the walls, ceiling, floor and light
	cube_mesh_idx := scene_add_mesh(&scene, create_cube())

	// Create the room box (scaling the cube to make walls)
	room_size: f32 = 5.0
	wall_thickness: f32 = 0.1

	// Floor (bottom wall)
	scene_add_object(
		&scene,
		"Floor",
		cube_mesh_idx,
		white_material_idx,
		position = {0, -room_size / 2, 0},
		scale = {room_size, wall_thickness, room_size},
	)

	// Ceiling (top wall)
	scene_add_object(
		&scene,
		"Ceiling",
		cube_mesh_idx,
		white_material_idx,
		position = {0, room_size / 2, 0},
		scale = {room_size, wall_thickness, room_size},
	)

	// Back wall
	scene_add_object(
		&scene,
		"Back Wall",
		cube_mesh_idx,
		white_material_idx,
		position = {0, 0, room_size / 2},
		scale = {room_size, room_size, wall_thickness},
	)

	// Left wall (green)
	scene_add_object(
		&scene,
		"Left Wall",
		cube_mesh_idx,
		green_material_idx,
		position = {-room_size / 2, 0, 0},
		scale = {wall_thickness, room_size, room_size},
	)

	// Right wall (red)
	scene_add_object(
		&scene,
		"Right Wall",
		cube_mesh_idx,
		red_material_idx,
		position = {room_size / 2, 0, 0},
		scale = {wall_thickness, room_size, room_size},
	)

	// Light (on the ceiling)
	light_size: f32 = 1.0
	scene_add_object(
		&scene,
		"Light",
		cube_mesh_idx,
		light_material_idx,
		position = {0, room_size / 2 - wall_thickness, 0},
		scale = {light_size, wall_thickness / 2, light_size},
	)

	// Add some objects inside the box
	sphere_mesh_idx := scene_add_mesh(&scene, create_sphere(stacks = 64, slices = 64))

	// Create a shiny/metallic material
	metallic_material_idx := len(scene.materials)
	scene_add_material(
		&scene,
		Material{name = "metallic", albedo = {0.8, 0.8, 0.8}, metallic = 1.0, roughness = 0.1},
	)

	// Create a glass material
	glass_material_idx := len(scene.materials)
	scene_add_material(
		&scene,
		Material {
			name = "glass",
			albedo = {1.0, 1.0, 1.0},
			transmission = 1.0,
			ior = 1.5,
			roughness = 0.0,
		},
	)

	// Add two spheres in the box
	scene_add_object(
		&scene,
		"Metal Sphere",
		sphere_mesh_idx,
		metallic_material_idx,
		position = {-1.0, -room_size / 2 + 1.0, -1.0},
		scale = {1.0, 1.0, 1.0},
	)

	scene_add_object(
		&scene,
		"Glass Sphere",
		sphere_mesh_idx,
		glass_material_idx,
		position = {1.5, -room_size / 2 + 0.5, 0.5},
		scale = {0.5, 0.5, 0.5},
	)

	return scene
}
