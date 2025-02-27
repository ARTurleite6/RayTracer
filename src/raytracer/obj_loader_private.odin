#+ private file

package raytracer

import "core:strconv"
import "core:strings"

@(private = "package")
Obj_Command :: struct {
	command_type: Obj_Command_Type,
	value:        union {
		string,
		[]f32,
		[]Vec3,
	},
}

Obj_Command_Type :: enum {
	Vertex,
	Texture_Vertex,
	Normal,
	Object,
	Face,
}

@(require_results)
@(private = "package")
parse_obj_file :: proc(content: string, allocator := context.allocator) -> []Obj_Command {
	content := content
	commands := make([dynamic]Obj_Command, allocator)
	for line in strings.split_lines_iterator(&content) {
		if line == "" || strings.starts_with(strings.trim_left(line, " \\s\\n"), "#") do continue

		iterator := line
		camp, _ := strings.fields_iterator(&iterator)

		switch camp {
		case "o":
			name, _ := strings.fields_iterator(&iterator)
			append(&commands, Obj_Command{command_type = .Object, value = name})
		case "v", "vt", "vn":
			values := make([dynamic]f32, allocator)
			for c in strings.fields_iterator(&iterator) {

				value, _ := strconv.parse_f32(c)
				append(&values, value)
			}
			append(&commands, Obj_Command{command_type = str_to_command(camp), value = values[:]})
		}
	}

	return commands[:]
}

str_to_command :: proc(str: string) -> Obj_Command_Type {
	switch str {
	case "v":
		return .Vertex
	case "vt":
		return .Texture_Vertex
	case "vn":
		return .Normal
	}
	return {}
}
