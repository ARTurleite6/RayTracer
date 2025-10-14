package raytracer

import "core:encoding/json"
import "core:fmt"
import "core:log"
import glm "core:math/linalg/glsl"
_ :: glm
import "core:os/os2"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "vendor:cgltf"

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
load_scene_from_gltf :: proc(scenepath: string) -> (scene: Scene, err: Scene_Load_Error) {
	start := time.tick_now()
	defer {
		log.infof("Scene %s loaded in %d", filepath.base(scenepath), time.tick_since(start))
	}

	scenepath := strings.clone_to_cstring(scenepath)
	defer delete(scenepath)
	options := cgltf.options {
		type = .glb,
	}
	data, result := cgltf.parse_file(options, scenepath)
	if result != .success {
		err = .Invalid_File
		return
	}

	if load_buffers_result := cgltf.load_buffers(options, data, scenepath);
	   load_buffers_result != .success {
		err = .Invalid_File
		return
	}
	assert(cgltf.validate(data) == .success)


	for material in data.materials {
		mat: Material
		mat.name = strings.clone_from_cstring(material.name)

		if material.has_pbr_metallic_roughness {
			pbr := material.pbr_metallic_roughness
			mat.albedo = pbr.base_color_factor.rgb
			mat.roughness = pbr.roughness_factor
			mat.metallic = pbr.metallic_factor
		}

		mat.emission_power = material.emissive_strength.emissive_strength
		mat.emission_color = material.emissive_factor

		append(&scene.materials, mat)
	}


	for mesh in data.meshes {
		m: Mesh
		m.name = strings.clone_from_cstring(mesh.name)

		for p in mesh.primitives {
			pos_accessor, norm_accessor: ^cgltf.accessor

			for a in p.attributes {
				#partial switch a.type {
				case .position:
					pos_accessor = a.data
				case .normal:
					norm_accessor = a.data
				}
			}

			vertices_count := pos_accessor.count
			vertices := make([]Vertex, vertices_count)

			for v in 0 ..< vertices_count {
				pos: [3]f32
				_ = cgltf.accessor_read_float(pos_accessor, v, raw_data(pos[:]), 3)
				vertices[v].pos = pos

				if norm_accessor != nil {
					norm: [3]f32
					_ = cgltf.accessor_read_float(norm_accessor, v, raw_data(norm[:]), 3)
					vertices[v].normal = norm
				}
			}

			indices := make([]u32, p.indices.count)
			for j in 0 ..< p.indices.count {
				indices[j] = u32(cgltf.accessor_read_index(p.indices, j))
			}

			m.vertices = vertices
			m.indices = indices
		}

		append(&scene.meshes, m)
	}

	index_by_name :: proc(s: []$T, name: string) -> (int, bool) {
		for m, i in s {
			if m.name == name {
				return i, true
			}
		}

		return {}, false
	}

	for &n in data.nodes {
		if n.mesh == nil {
			continue
		}

		obj: Object
		obj.name = strings.clone_from_cstring(n.name)
		// tr, rot, scale: Vec3
		mat4: Mat4

		// TODO: check if I need to change Mat4 to row_major
		cgltf.node_transform_local(&n, &mat4[0, 0])
		obj.transform.model_matrix = glm.mat4Rotate({1, 0, 0}, glm.radians(f32(90.0))) * mat4
		// obj.transform.position = extrag
		obj.transform.normal_matrix = glm.inverse_transpose_matrix4x4(mat4)
		mesh_index, ok := index_by_name(
			scene.meshes[:],
			strings.clone_from_cstring(n.mesh.name, context.temp_allocator),
		)
		assert(ok)
		obj.mesh_index = mesh_index
		material_index, material_ok := index_by_name(
			scene.materials[:],
			strings.clone_from_cstring(n.mesh.primitives[0].material.name, context.temp_allocator),
		)
		assert(material_ok)
		obj.material_index = material_index
		append(&scene.objects, obj)
	}

	fmt.println(scene.meshes)
	fmt.println(scene.materials)
	fmt.println(scene.objects)

	return
}

@(require_results)
load_scene_from_file :: proc(scenepath: string) -> (scene: Scene, err: Scene_Load_Error) {
	start := time.tick_now()
	defer {
		log.infof("Scene %s loaded in %d", filepath.base(scenepath), time.tick_since(start))
	}
	scene_loader: Scene_Loader
	data, file_err := os2.read_entire_file(scenepath, context.temp_allocator)
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
