package raytracer

import "core:log"
import "core:math"
import glm "core:math/linalg/glsl"
import "core:slice"
import "core:strings"
_ :: log

Vertex :: struct {
	pos:    Vec3,
	normal: Vec3,
}

Scene_Change_Type :: enum {
	Material_Changed,
	Material_Added,
	Material_Removed,
	Object_Material_Changed,
	Object_Added,
	Object_Removed,
	Object_Transform_Changed,
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
	position:      Vec3,
	rotation:      Vec3,
	scale:         Vec3,
	model_matrix:  Mat4,
	normal_matrix: Mat4,
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
	for &object in scene.objects {
		delete(object.name)
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

scene_update_object_material :: proc(scene: ^Scene, object_idx, new_material_idx: int) {
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
		name           = strings.clone(name),
		transform      = transform,
		mesh_index     = mesh_index,
		material_index = material_index,
	}
	object_update_model_matrix(&object)

	append(&scene.changes, Scene_Change{type = .Object_Added})
	append(&scene.objects, object)
	return len(scene.objects) - 1
}

object_update_position :: proc(object: ^Object, new_pos: Vec3) {
	object.transform.position = new_pos
	object_update_model_matrix(object)
}

object_update_model_matrix :: proc(object: ^Object) {
	transform := &object.transform
	rot :=
		glm.mat4Rotate({1, 0, 0}, glm.radians(object.transform.rotation.x)) *
		glm.mat4Rotate({0, 1, 0}, glm.radians(object.transform.rotation.y)) *
		glm.mat4Rotate({0, 0, 1}, glm.radians(object.transform.rotation.z))

	transform.model_matrix =
		glm.mat4Translate(transform.position) * rot * glm.mat4Scale(transform.scale)

	transform.normal_matrix = glm.inverse_transpose(transform.model_matrix)
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

	append(&vertices, Vertex{pos = {0, 1, 0}, normal = {0, 1, 0}}) // north pole

	for i in 0 ..< stacks - 1 {
		phi := math.PI * f32(i + 1) / f32(stacks)
		for j in 0 ..< slices {
			theta := 2.0 * math.PI * f32(j) / f32(slices)
			x := math.sin(phi) * math.cos(theta)
			y := math.cos(phi)
			z := math.sin(phi) * math.sin(theta)

			append(&vertices, Vertex{pos = {x, y, z}, normal = {x, y, z}})
		}
	}

	append(&vertices, Vertex{pos = {0, -1, 0}, normal = {0, -1, 0}}) // north pole

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
	// TODO: for now lets handle this type of object like this but probably later lets just disable cull
	vertices := []Vertex {
		{{-0.5, -0.5, 0}, {0, 0, 1}}, // 0: bottom-left
		{{0.5, -0.5, 0}, {0, 0, 1}}, // 1: bottom-right
		{{0.5, 0.5, 0}, {0, 0, 1}}, // 2: top-right
		{{-0.5, 0.5, 0}, {0, 0, 1}}, // 3: top-left
	}

	indices := []u32 {
		// Front face
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

@(private)
create_scene :: proc() -> (scene: Scene) {
	return create_cornell_box()
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
			emission_power = 10.0,
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
		rotation = {-90, 0, 0},
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
		rotation = {0, 180, 0},
	)

	// Left wall (green)
	scene_add_object(
		&scene,
		"Left Wall",
		plane_mesh_idx,
		green_material_idx,
		position = {-room_size / 2, 0, 0},
		scale = {room_size, room_size, room_size},
		rotation = {0, -90, 0},
	)

	// 	Rightwall(red)
	scene_add_object(
		&scene,
		"Right Wall",
		plane_mesh_idx,
		red_material_idx,
		position = {room_size / 2, 0, 0},
		scale = {room_size, room_size, room_size},
		rotation = {0, 90, 0},
	)


	sphere_mesh_idx := scene_add_mesh(&scene, create_sphere())

	// Light (on the ceiling)
	light_size: f32 = 1.0
	scene_add_object(
		&scene,
		"Light Center",
		plane_mesh_idx,
		light_material_idx,
		position = {0, -(room_size / 2 - 0.1), 0},
		scale = {light_size, light_size, light_size},
		rotation = {-90, 0, 0},
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
			roughness = 1.0, // Fairly smooth surface
		},
	)

	// Add two spheres in the box
	scene_add_object(
		&scene,
		"Metal Sphere",
		sphere_mesh_idx,
		metallic_material_idx,
		position = {-1.0, -(-room_size / 2 + 1.0), -1.0},
		scale = {1.0, 1.0, 1.0},
	)

	scene_add_object(
		&scene,
		"Glossy Sphere",
		sphere_mesh_idx,
		glossy_material_idx,
		position = {1.5, -(-room_size / 2 + 1.0), 0.5},
		scale = {0.5, 0.5, 0.5},
	)

	return scene
}
