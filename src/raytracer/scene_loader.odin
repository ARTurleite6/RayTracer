package raytracer

import "base:intrinsics"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import glm "core:math/linalg/glsl"
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
	None = 0,
	Invalid_File,
	Object_Material_Not_Found,
}

@(require_results)
load_scene_from_gltf :: proc(scenepath: string) -> (scene: Scene, err: Scene_Load_Error) {
	start := time.tick_now()
	defer {
		log.infof("Scene %s loaded in %d", filepath.base(scenepath), time.tick_since(start))
	}

	scenepath_c := strings.clone_to_cstring(scenepath)
	defer delete(scenepath_c)

	ext := filepath.ext(scenepath)
	ft := cgltf.file_type.invalid
	switch (ext) {
	case ".gltf":
		ft = .gltf
	case ".glb":
		ft = .glb
	case:
		ft = .invalid
	}

	options := cgltf.options {
		type = ft,
	}

	data, result := cgltf.parse_file(options, scenepath_c)
	if result != .success {
		err = .Invalid_File
		return
	}
	defer cgltf.free(data)

	// load buffers using directory of the glTF file
	// base_dir := filepath.dir(scenepath)
	// base_c := strings.clone_to_cstring(base_dir)
	// defer delete(base_c)
	if cgltf.load_buffers(options, data, scenepath_c) != .success {
		err = .Invalid_File
		return
	}

	assert(cgltf.validate(data) == .success)

	// ---------- Materials ----------
	for material in data.materials {
		mat: Material
		mat.name = strings.clone_from_cstring(material.name)

		if material.has_pbr_metallic_roughness {
			pbr := material.pbr_metallic_roughness
			mat.albedo = pbr.base_color_factor.rgb
			mat.roughness = pbr.roughness_factor
			mat.metallic = pbr.metallic_factor
		}

		mat.emission_color = material.emissive_factor
		if material.has_emissive_strength {
			mat.emission_power = material.emissive_strength.emissive_strength
		} else {
			mat.emission_power = 0.0
		}

		append(&scene.materials, mat)
	}

	// ---------- Meshes + Objects ----------
	for &n in data.nodes {
		if n.mesh == nil {
			continue
		}

		world: Mat4
		cgltf.node_transform_local(&n, &world[0, 0])

		for p in n.mesh.primitives {
			m: Mesh
			m.name = strings.clone_from_cstring(n.mesh.name)

			// --- Attributes ---
			pos_accessor: ^cgltf.accessor = nil
			norm_accessor: ^cgltf.accessor = nil

			for a in p.attributes {
				#partial switch a.type {
				case .position:
					pos_accessor = a.data
				case .normal:
					norm_accessor = a.data
				}
			}

			assert(pos_accessor != nil)
			vertex_count := pos_accessor.count
			verts := make([]Vertex, vertex_count)

			for v in 0 ..< vertex_count {
				pos: [3]f32
				_ = cgltf.accessor_read_float(pos_accessor, v, raw_data(pos[:]), 3)
				verts[v].pos = pos

				if norm_accessor != nil {
					nrm: [3]f32
					_ = cgltf.accessor_read_float(norm_accessor, v, raw_data(nrm[:]), 3)
					verts[v].normal = nrm
				}
			}

			inds: []u32
			if p.indices != nil {
				inds = make([]u32, p.indices.count)
				for j in 0 ..< p.indices.count {
					inds[j] = u32(cgltf.accessor_read_index(p.indices, j))
				}
			} else {
				inds = make([]u32, vertex_count)
				for j in 0 ..< vertex_count {
					inds[j] = u32(j)
				}
			}

			m.vertices = verts
			m.indices = inds

			append(&scene.meshes, m)
			mesh_index := len(scene.meshes) - 1

			// --- Material index (by pointer offset) ---
			mat_index := -1
			if p.material != nil {
				mat_index = int(
					(uintptr(p.material) - uintptr(&data.materials[0])) / size_of(cgltf.material),
				)
			}

			// --- Object instance ---
			obj: Object
			obj.name = strings.clone_from_cstring(n.name)
			obj.transform = {
				model_matrix  = world,
				normal_matrix = glm.inverse_transpose_matrix4x4(world),
				position      = n.translation,
				scale         = n.scale,
				rotation      = n.rotation.xyz,
			}

			// object_update_model_matrix(&obj)

			obj.mesh_index = u32(mesh_index)
			if mat_index >= 0 {obj.material_index = u32(mat_index)}
			append(&scene.objects, obj)
		}
	}

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

