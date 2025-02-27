package bindings

foreign import tinyobj_loader "../build/libtinyobjloader-c.a"

import "core:c"

Vec3 :: [3]f32

tinyobj_attrib_t :: struct {
	num_vertices:       c.uint,
	num_normals:        c.uint,
	num_texcoords:      c.uint,
	num_faces:          c.uint,
	num_face_num_verts: c.uint,
	pad0:               c.int,
	vertices:           [^]c.float,
	normals:            [^]c.float,
	texcoords:          [^]c.float,
	faces:              [^]tinyobj_vertex_index_t,
	face_num_verts:     [^]c.int,
	material_ids:       [^]c.int,
}

tinyobj_vertex_index_t :: struct {
	v_idx, vt_idx, vn_idx: c.int,
}

tinyobj_shape_t :: struct {
	name:        cstring,
	face_offset: c.uint,
	length:      c.uint,
}

tinyobj_material_t :: struct {
	name:                                                                         cstring,
	ambient, diffuse, specular, transmittance, emission:                          Vec3,
	shininess, ior, dissolve:                                                     c.float,
	illum, pad0:                                                                  c.int,
	ambient_texname, diffuse_texname, specular_texname:                           cstring,
	specular_highligh_texname, bump_texname, displacement_texname, alpha_texname: cstring,
}

Flag :: enum {
	Triangulate = 1,
}
Flags :: bit_set[Flag]

file_reader_callback :: #type proc "c" (
	ctx: rawptr,
	filename: cstring,
	is_mtl: b32,
	obj_filename: cstring,
	buf: ^[^]c.char,
	len: ^c.size_t,
)

@(default_calling_convention = "c")
foreign tinyobj_loader {
	tinyobj_parse_obj :: proc(attrib: ^tinyobj_attrib_t, shapes: ^[^]tinyobj_shape_t, num_shapes: ^c.size_t, materials: ^[^]tinyobj_material_t, num_materials: ^c.size_t, filename: cstring, file_reader: file_reader_callback, ctx: rawptr, flags: Flags) -> c.int ---
	tinyobj_attrib_free :: proc(attrib: ^tinyobj_attrib_t) ---
	tinyobj_shapes_free :: proc(shapes: [^]tinyobj_shape_t, num_shapes: c.size_t) ---
	tinyobj_materials_free :: proc(materials: [^]tinyobj_material_t, num_materials: c.size_t) ---
}
