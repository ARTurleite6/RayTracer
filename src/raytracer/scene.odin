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

Scene_Change_Type :: enum {
	Material_Changed,
	Material_Added,
	Material_Removed,
	Object_Transform_Changed,
	Object_Material_Changed,
	Mesh_Changed,
	Full_Rebuild,
}

Scene_Change :: struct {
	type:  Scene_Change_Type,
	index: int, // Often points to the changed object/material
}

Scene :: struct {
	meshes:    [dynamic]Mesh,
	objects:   [dynamic]Object,
	materials: [dynamic]Material,

	// state tracking
	// TODO: I need to see this better in the future
	changes:   [dynamic]Scene_Change,
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

scene_init :: proc(scene: ^Scene, allocator := context.allocator) {
	scene.changes.allocator = allocator
}

scene_destroy :: proc(scene: ^Scene) {
	for &mesh in scene.meshes {
		mesh_destroy(&mesh)
	}

	delete(scene.meshes)
	delete(scene.objects)
	delete(scene.materials)
	delete(scene.changes)
	scene^ = {}
}

scene_add_material :: proc(scene: ^Scene, material: Material) {
	append(&scene.materials, material)
	append(&scene.changes, Scene_Change{type = .Material_Added, index = len(scene.materials) - 1})
}

scene_get_material_name :: proc(scene: Scene, material_id: int) -> string {
	return scene.materials[material_id].name
}

scene_delete_material :: proc(scene: ^Scene, material_index: int) {
	material := scene.materials[material_index]
	delete(material.name)
	unordered_remove(&scene.materials, material_index)

	for object, i in scene.objects {
		if object.material_index == material_index {
			scene_update_object_material(scene, i, 0)
		}
	}

	append(&scene.changes, Scene_Change{type = .Material_Removed, index = material_index})
}

scene_update_material :: proc(scene: ^Scene, material_idx: int, material: Material) {
	scene.materials[material_idx] = material
	append(&scene.changes, Scene_Change{type = .Material_Changed, index = material_idx})
}

scene_update_object_material :: proc(scene: ^Scene, object_idx: int, new_material_idx: int) {
	scene.objects[object_idx].material_index = new_material_idx
	append(&scene.changes, Scene_Change{type = .Object_Material_Changed, index = object_idx})
}

scene_add_mesh :: proc(scene: ^Scene, mesh: Mesh) -> int {
	append(&scene.meshes, mesh)
	return len(scene.meshes) - 1
}

scene_get_mesh_name :: proc(scene: ^Scene, mesh_id: int) -> string {
	return scene.meshes[mesh_id].name
}

scene_update_object_position :: proc(scene: ^Scene, object_index: int, new_position: Vec3) {
	object := &scene.objects[object_index]
	object_update_position(object, new_position)

	append(&scene.changes, Scene_Change{type = .Object_Transform_Changed, index = object_index})
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
		glm.matrix4_translate(transform.position) *
		glm.matrix4_from_euler_angles_xyz_f32(
			glm.to_radians(object.transform.rotation.x),
			glm.to_radians(object.transform.rotation.y),
			glm.to_radians(object.transform.rotation.z),
		) *
		glm.matrix4_scale_f32(transform.scale)
}

mesh_init :: proc(mesh: ^Mesh, vertices: []Vertex, indices: []u32, name: string) -> Mesh_Error {
	mesh^ = {
		name     = strings.clone(name),
		vertices = slice.clone(vertices),
		indices  = slice.clone(indices),
	}
	return nil
}

mesh_destroy :: proc(mesh: ^Mesh) {
	delete(mesh.name)
	delete(mesh.vertices)
	delete(mesh.indices)
}

create_sphere :: proc(stacks: int = 32, slices: int = 32) -> (mesh: Mesh) {
	vertices := make([dynamic]Vertex, context.temp_allocator)
	indices := make([dynamic]u32, context.temp_allocator)

	append(&vertices, Vertex{pos = {0, 1, 0}, normal = {0, 1, 0}, color = {}}) // north pole

	for i in 0 ..< stacks - 1 {
		phi := math.PI * f32(i + 1) / f32(stacks)
		for j in 0 ..< slices {
			theta := 2.0 * math.PI * f32(j) / f32(slices)
			x := math.sin(phi) * math.cos(theta)
			y := math.cos(phi)
			z := math.sin(phi) * math.sin(theta)

			append(&vertices, Vertex{pos = {x, y, z}, normal = {x, y, z}, color = {}})
		}
	}

	append(&vertices, Vertex{pos = {0, -1, 0}, normal = {0, -1, 0}, color = {}}) // north pole

	for i in 0 ..< slices {
		i0 := i + 1
		i1 := (i + 1) % slices + 1
		append(&indices, 0) // north pole
		append(&indices, u32(i1))
		append(&indices, u32(i0))

		i0 = i + slices * (stacks - 2) + 1
		i1 = (i + 1) % slices + slices * (stacks - 2) + 1
		append(&indices, u32(len(vertices) - 1)) // south pole
		append(&indices, u32(i0))
		append(&indices, u32(i1))
	}

	for j in 0 ..< stacks - 2 {
		j0 := j * slices + 1
		j1 := (j + 1) * slices + 1
		for i in 0 ..< slices {
			i0 := j0 + i
			i1 := j0 + (i + 1) % slices
			i2 := j1 + (i + 1) % slices
			i3 := j1 + i

			append(&indices, u32(i0))
			append(&indices, u32(i1))
			append(&indices, u32(i2))

			append(&indices, u32(i0))
			append(&indices, u32(i2))
			append(&indices, u32(i3))
		}
	}

	mesh_init(&mesh, vertices[:], indices[:], "Sphere")
	return mesh
}

create_plane :: proc(width: f32 = 1.0, height: f32 = 1.0) -> (mesh: Mesh) {
	vertices := []Vertex {
		// Plane in XY plane, facing +Z (normal: 0, 0, 1)
		// Counter-clockwise when viewed from +Z
		{{-0.5, -0.5, 0}, {0, 0, 1}, {0, 0, 1}}, // 0: bottom-left
		{{0.5, -0.5, 0}, {0, 0, 1}, {1, 0, 0}}, // 1: bottom-right
		{{0.5, 0.5, 0}, {0, 0, 1}, {1, 1, 0}}, // 2: top-right
		{{-0.5, 0.5, 0}, {0, 0, 1}, {0, 1, 0}}, // 3: top-left
	}

	indices := []u32 {
		0,
		1,
		2, // First triangle
		0,
		2,
		3, // Second triangle
	}

	mesh_init(&mesh, vertices, indices, "Plane")
	return mesh
}

create_cube_simple :: proc() -> (mesh: Mesh) {
	// Define the 8 corner positions
	positions := []Vec3 {
		{-0.5, -0.5, -0.5}, // 0: left-bottom-back
		{0.5, -0.5, -0.5}, // 1: right-bottom-back
		{0.5, 0.5, -0.5}, // 2: right-top-back
		{-0.5, 0.5, -0.5}, // 3: left-top-back
		{-0.5, -0.5, 0.5}, // 4: left-bottom-front
		{0.5, -0.5, 0.5}, // 5: right-bottom-front
		{0.5, 0.5, 0.5}, // 6: right-top-front
		{-0.5, 0.5, 0.5}, // 7: left-top-front
	}

	vertices := []Vertex {
		// Front face (z = +0.5, normal: 0, 0, 1)
		{positions[4], {0, 0, 1}, {1, 0, 0}}, // 0
		{positions[5], {0, 0, 1}, {0, 1, 0}}, // 1
		{positions[6], {0, 0, 1}, {0, 0, 1}}, // 2
		{positions[7], {0, 0, 1}, {1, 1, 0}}, // 3

		// Back face (z = -0.5, normal: 0, 0, -1)
		{positions[1], {0, 0, -1}, {0, 1, 1}}, // 4
		{positions[0], {0, 0, -1}, {1, 0, 1}}, // 5
		{positions[3], {0, 0, -1}, {0, 0, 0}}, // 6
		{positions[2], {0, 0, -1}, {1, 1, 1}}, // 7

		// Right face (x = +0.5, normal: 1, 0, 0)
		{positions[5], {1, 0, 0}, {0, 1, 0}}, // 8
		{positions[1], {1, 0, 0}, {0, 1, 1}}, // 9
		{positions[2], {1, 0, 0}, {1, 1, 1}}, // 10
		{positions[6], {1, 0, 0}, {0, 0, 1}}, // 11

		// Left face (x = -0.5, normal: -1, 0, 0)
		{positions[0], {-1, 0, 0}, {1, 0, 1}}, // 12
		{positions[4], {-1, 0, 0}, {1, 0, 0}}, // 13
		{positions[7], {-1, 0, 0}, {1, 1, 0}}, // 14
		{positions[3], {-1, 0, 0}, {0, 0, 0}}, // 15

		// Top face (y = +0.5, normal: 0, 1, 0)
		{positions[7], {0, 1, 0}, {1, 1, 0}}, // 16
		{positions[6], {0, 1, 0}, {0, 0, 1}}, // 17
		{positions[2], {0, 1, 0}, {1, 1, 1}}, // 18
		{positions[3], {0, 1, 0}, {0, 0, 0}}, // 19

		// Bottom face (y = -0.5, normal: 0, -1, 0)
		{positions[0], {0, -1, 0}, {1, 0, 1}}, // 20
		{positions[1], {0, -1, 0}, {0, 1, 1}}, // 21
		{positions[5], {0, -1, 0}, {0, 1, 0}}, // 22
		{positions[4], {0, -1, 0}, {1, 0, 0}}, // 23
	}

	indices := []u32 {
		// All faces use counter-clockwise winding when viewed from outside
		0,
		1,
		2,
		0,
		2,
		3, // Front
		4,
		5,
		6,
		4,
		6,
		7, // Back
		8,
		9,
		10,
		8,
		10,
		11, // Right
		12,
		13,
		14,
		12,
		14,
		15, // Left
		16,
		17,
		18,
		16,
		18,
		19, // Top
		20,
		21,
		22,
		20,
		22,
		23, // Bottom
	}

	mesh_init(&mesh, vertices, indices, "Cube")
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
			emission_power = 5.0,
		},
	)

	// Create a cube mesh for the walls, ceiling, floor and light
	// cube_mesh_idx := scene_add_mesh(&scene, create_cube_simple())
	plane_mesh_idx := scene_add_mesh(&scene, create_plane())

	// Create the room box (scaling the cube to make walls)
	room_size: f32 = 5.0

	scene_add_object(
		&scene,
		"Floor",
		plane_mesh_idx,
		white_material_idx,
		position = {0, -room_size / 2, 0},
		scale = {room_size, room_size, room_size},
		rotation = {90, 0, 0},
	)


	// Ceiling (top wall)
	scene_add_object(
		&scene,
		"Ceiling",
		plane_mesh_idx,
		white_material_idx,
		position = {0, room_size / 2, 0},
		scale = {room_size, room_size, room_size},
		rotation = {90, 0, 0},
	)

	// Back wall
	scene_add_object(
		&scene,
		"Back Wall",
		plane_mesh_idx,
		green_material_idx,
		position = {0, 0, room_size / 2},
		scale = {room_size, room_size, room_size},
	)

	// Left wall (green)
	scene_add_object(
		&scene,
		"Left Wall",
		plane_mesh_idx,
		green_material_idx,
		position = {-room_size / 2, 0, 0},
		scale = {room_size, room_size, room_size},
		rotation = {0, 90, 0},
	)

	// 	Rightwall(red)
	scene_add_object(
		&scene,
		"Right Wall",
		plane_mesh_idx,
		red_material_idx,
		position = {room_size / 2, 0, 0},
		scale = {room_size, room_size, room_size},
		rotation = {0, -90, 0},
	)


	sphere_mesh_idx := scene_add_mesh(&scene, create_sphere())

	// Light (on the ceiling)
	light_size: f32 = 1.0
	scene_add_object(
		&scene,
		"Light Center",
		plane_mesh_idx,
		light_material_idx,
		position = {0, room_size / 2 - 0.1, 0},
		scale = {light_size, light_size, light_size},
		rotation = {90, 0, 0},
	)

	// Add some objects inside the box

	// Create a shiny/metallic material
	metallic_material_idx := len(scene.materials)
	scene_add_material(
		&scene,
		Material{name = "metallic", albedo = {0.8, 0.8, 0.8}, metallic = 1.0, roughness = 0.1},
	)

	// Create a glossy material (lower roughness but not metallic)
	glossy_material_idx := len(scene.materials)
	scene_add_material(
		&scene,
		Material {
			name      = "glossy",
			albedo    = {0.3, 0.8, 0.3}, // Green glossy material
			metallic  = 0.0, // Not a metal
			roughness = 0.2, // Fairly smooth surface
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
		"Glossy Sphere",
		sphere_mesh_idx,
		glossy_material_idx,
		position = {1.5, -room_size / 2 + 0.5, 0.5},
		scale = {0.5, 0.5, 0.5},
	)

	return scene
}
