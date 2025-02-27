package raytracer

import "base:runtime"
import "core:os"
import "core:strings"

Obj_Load_Error :: union {
	os.Error,
	Obj_Parse_Error,
}

Obj_Parse_Error :: struct {
	line:   string,
	reason: Obj_Parse_Error_Reason,
}

Obj_Parse_Error_Reason :: enum {
	Field_Missing,
	Field_Type_Invalid,
}

Obj_Scene :: struct {
	objects:          []Object,
	vertices:         []Vec4,
	texture_vertices: []Vec3,
	normals:          []Vec3,
}

Obj_Object :: struct {
	name:  string,
	faces: []Face,
}

Face :: struct {
	vertice_index:               int,
	texture_index, normal_index: Maybe(int),
}

load_obj_file :: proc(
	filepath: string,
	allocator := context.allocator,
) -> (
	scene: Obj_Scene,
	err: Obj_Load_Error,
) {
	vertices := make([dynamic]Vec4, allocator)
	texture_vertices := make([dynamic]Vec3, allocator)
	normals := make([dynamic]Vec3, allocator)
	objects := make([dynamic]Object, allocator)
	defer if err != nil {
		delete(vertices)
		delete(texture_vertices)
		delete(normals)
		delete(objects)
	}

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == context.temp_allocator)
	data := os.read_entire_file_or_err(filepath, context.temp_allocator) or_return
	content := string(data)

	commands := parse_obj_file(content, context.temp_allocator)

	for c in commands {
		#partial switch c.command_type {
		case .Object:
			append(&objects, Object{name = strings.clone(c.value.(string), allocator)})
		case .Texture_Vertex:
			value := c.value.([]f32)
			vertex: Vec3
			vertex.x = value[0]
			if len(value) >= 2 {
				vertex.y = value[1]
			}
			if len(value) == 3 {
				vertex.y = value[2]
			}

		case .Vertex, .Normal:
			value := c.value.([]f32)
			vertex: Vec4
			vertex.x = value[0]
			vertex.y = value[1]
			vertex.z = value[2]
			if c.command_type == .Vertex {
				vertex.w = 1
				if len(value) == 4 {
					vertex.w = value[3]
				}
				append(&vertices, vertex)
			} else if c.command_type == .Normal {
				append(&normals, vertex.xyz)
			}
		}
	}

	scene.objects = objects[:]
	scene.vertices = vertices[:]
	scene.normals = normals[:]

	return scene, nil
}
