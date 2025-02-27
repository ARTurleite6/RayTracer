package odin_tinyobjloader

import "base:runtime"
import "bindings"
import "core:c"
import "core:c/libc"
import "core:os"

Scene :: struct {
	shapes:     []Shape,
	materials:  []Material,
	attributes: Attributes,
}

Attributes :: struct {
	vertices:       []f32,
	normals:        []f32,
	texcoords:      []f32,
	faces:          []Vertex_Index,
	face_num_verts: []i32,
	material_ids:   []i32,
}

Vertex_Index :: bindings.tinyobj_vertex_index_t
Material :: bindings.tinyobj_material_t
Shape :: bindings.tinyobj_shape_t
Flag :: bindings.Flag
Flags :: bindings.Flags

parse_obj :: proc(
	filename: string,
	flags: Flags = {.Triangulate},
	allocator := context.allocator,
) -> (
	scene: Scene,
	ok: b32,
) {
	attrib: bindings.tinyobj_attrib_t
	shapes: [^]bindings.tinyobj_shape_t
	num_shapes: c.size_t
	materials: [^]bindings.tinyobj_material_t
	num_materials: c.size_t

	if result := bindings.tinyobj_parse_obj(
		&attrib,
		&shapes,
		&num_shapes,
		&materials,
		&num_materials,
		"quad.obj",
		default_file_reader,
		nil,
		flags,
	); result != 0 {
		return {}, false
	}

	scene.shapes = shapes[:num_shapes]
	scene.attributes.faces = attrib.faces[:attrib.num_faces]
	scene.attributes.vertices = attrib.vertices[:attrib.num_vertices]
	scene.attributes.normals = attrib.normals[:attrib.num_normals]
	scene.attributes.texcoords = attrib.texcoords[:attrib.num_texcoords]
	scene.attributes.face_num_verts = attrib.face_num_verts[:attrib.num_face_num_verts]
	scene.attributes.material_ids = attrib.material_ids[:attrib.num_face_num_verts]
	scene.materials = materials[:num_materials]

	return {}, true
}

scene_destroy :: proc(scene: ^Scene) {
	bindings.tinyobj_materials_free(raw_data(scene.materials), len(scene.materials))
	bindings.tinyobj_shapes_free(raw_data(scene.shapes), len(scene.shapes))

	libc.free(raw_data(scene.attributes.vertices))
	libc.free(raw_data(scene.attributes.normals))
	libc.free(raw_data(scene.attributes.texcoords))
	libc.free(raw_data(scene.attributes.faces))
	libc.free(raw_data(scene.attributes.face_num_verts))
	libc.free(raw_data(scene.attributes.material_ids))
}

default_file_reader :: proc "c" (
	ctx: rawptr,
	filename: cstring,
	is_mtl: b32,
	obj_filename: cstring,
	buf: ^[^]c.char,
	length: ^c.size_t,
) {
	context = runtime.default_context()

	data, _ := os.read_entire_file_from_filename(string(filename))

	buf^ = &data[0]
	length^ = len(data)
}
