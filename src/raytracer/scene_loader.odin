package raytracer

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os/os2"
import "core:strings"

Scene_Loader :: struct {
	materials: map[string]Material,
	objects:   map[string]Object_Loader,
}

Object_Loader :: struct {
	material:  string,
	mesh:      Mesh_Variant,
	transform: Transform,
}

Mesh_Variant :: enum {
	Plane,
	Sphere,
}

Scene_Load_Error :: enum {
	Invalid_File,
	Object_Material_Not_Found,
}

@(require_results)
load_scene_from_file :: proc(filepath: string) -> (scene: Scene, err: Scene_Load_Error) {
	scene_loader: Scene_Loader
	data, file_err := os2.read_entire_file(filepath, context.temp_allocator)
	if file_err != nil {
		return {}, .Invalid_File
	}

	if err := json.unmarshal(data, &scene_loader, allocator = context.temp_allocator); err != nil {
		log.errorf("Error parsing scene: %v", err)
		return {}, .Invalid_File
	}

	defer if err != nil {
		scene_destroy(&scene)
	}

	for name, &material in scene_loader.materials {
		material.name = strings.clone(name)
		scene_add_material(&scene, material)
	}

	find_material :: proc(scene: Scene, material_name: string) -> (index: int, ok: bool) {
		for material, i in scene.materials {
			if material.name == material_name {
				return i, true
			}
		}
		return {}, false
	}

	meshes_arr: [Mesh_Variant]int = {
		.Plane  = scene_add_mesh(&scene, create_plane()),
		.Sphere = scene_add_mesh(&scene, create_sphere()),
	}

	for name, object in scene_loader.objects {
		material_idx, material_ok := find_material(scene, object.material)
		if !material_ok {
			fmt.eprintfln(
				"Error loading scene: Object '%s' has material '%s' that was not defined",
				name,
				object.material,
			)
			return {}, .Object_Material_Not_Found
		}
		scene_add_object(
			&scene,
			name,
			meshes_arr[object.mesh],
			material_idx,
			object.transform.position,
			object.transform.rotation,
			object.transform.scale,
		)
	}
	return scene, nil
}
