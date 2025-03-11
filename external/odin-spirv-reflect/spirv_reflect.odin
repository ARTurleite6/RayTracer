package spirv_reflect

import "core:c"

foreign import spirv "SPIRV-Reflect/build/libspirv-reflect-static.a"

Flag :: distinct u32

MAX_ARRAY_DIMS :: 32
MAX_DESCRIPTOR_SETS :: 64

Result :: enum {
	SUCCESS,
	NOT_READY,
	ERROR_PARSE_FAILED,
	ERROR_ALLOC_FAILED,
	ERROR_RANGE_EXCEEDED,
	ERROR_NULL_POINTER,
	ERROR_INTERNAL_ERROR,
	ERROR_COUNT_MISMATCH,
	ERROR_ELEMENT_NOT_FOUND,
	ERROR_SPIRV_INVALID_CODE_SIZE,
	ERROR_SPIRV_INVALID_MAGIC_NUMBER,
	ERROR_SPIRV_UNEXPECTED_EOF,
	ERROR_SPIRV_INVALID_ID_REFERENCE,
	ERROR_SPIRV_SET_NUMBER_OVERFLOW,
	ERROR_SPIRV_INVALID_STORAGE_CLASS,
	ERROR_SPIRV_RECURSION,
	ERROR_SPIRV_INVALID_INSTRUCTION,
	ERROR_SPIRV_UNEXPECTED_BLOCK_DATA,
	ERROR_SPIRV_INVALID_BLOCK_MEMBER_REFERENCE,
	ERROR_SPIRV_INVALID_ENTRY_POINT,
	ERROR_SPIRV_INVALID_EXECUTION_MODE,
	ERROR_SPIRV_MAX_RECURSIVE_EXCEEDED,
}

Generator :: enum {
	KHRONOS_LLVM_SPIRV_TRANSLATOR         = 6,
	KHRONOS_SPIRV_TOOLS_ASSEMBLER         = 7,
	KHRONOS_GLSLANG_REFERENCE_FRONT_END   = 8,
	GOOGLE_SHADERC_OVER_GLSLANG           = 13,
	GOOGLE_SPIREGG                        = 14,
	GOOGLE_RSPIRV                         = 15,
	X_LEGEND_MESA_MESAIR_SPIRV_TRANSLATOR = 16,
	KHRONOS_SPIRV_TOOLS_LINKER            = 17,
	WINE_VKD3D_SHADER_COMPILER            = 18,
	CLAY_CLAY_SHADER_COMPILER             = 19,
}

SourceLanguage :: enum {
	Unknown        = 0,
	ESSL           = 1,
	GLSL           = 2,
	OpenCL_C       = 3,
	OpenCL_CPP     = 4,
	HLSL           = 5,
	CPP_for_OpenCL = 6,
	SYCL           = 7,
	HERO_C         = 8,
	NZSL           = 9,
	Max            = 0x7fffffff,
}

ExecutionModel :: enum {
	Vertex                 = 0,
	TessellationControl    = 1,
	TessellationEvaluation = 2,
	Geometry               = 3,
	Fragment               = 4,
	GLCompute              = 5,
	Kernel                 = 6,
	TaskNV                 = 5267,
	MeshNV                 = 5268,
	RayGenerationKHR       = 5313,
	RayGenerationNV        = 5313,
	IntersectionKHR        = 5314,
	IntersectionNV         = 5314,
	AnyHitKHR              = 5315,
	AnyHitNV               = 5315,
	ClosestHitKHR          = 5316,
	ClosestHitNV           = 5316,
	MissKHR                = 5317,
	MissNV                 = 5317,
	CallableKHR            = 5318,
	CallableNV             = 5318,
	TaskEXT                = 5364,
	MeshEXT                = 5365,
	Max                    = 0x7fffffff,
}


EntryPoint :: struct {
}

Capability :: struct {
}

ShaderStageFlag :: enum {
	VERTEX                  = 0x00000001, // = VK_SHADER_STAGE_VERTEX
	TESSELLATION_CONTROL    = 0x00000002, // = VK_SHADER_STAGE_TESSELLATION_CONTROL
	TESSELLATION_EVALUATION = 0x00000004, // = VK_SHADER_STAGE_TESSELLATION_EVALUATION
	GEOMETRY                = 0x00000008, // = VK_SHADER_STAGE_GEOMETRY
	FRAGMENT                = 0x00000010, // = VK_SHADER_STAGE_FRAGMENT
	COMPUTE                 = 0x00000020, // = VK_SHADER_STAGE_COMPUTE
	TASK_NV                 = 0x00000040, // = VK_SHADER_STAGE_TASK_NV
	TASK_EXT                = TASK_NV, // = VK_SHADER_STAGE_CALLABLE_EXT
	MESH_NV                 = 0x00000080, // = VK_SHADER_STAGE_MESH_NV
	MESH_EXT                = MESH_NV, // = VK_SHADER_STAGE_CALLABLE_EXT
	RAYGEN_KHR              = 0x00000100, // = VK_SHADER_STAGE_RAYGEN_KHR
	ANY_HIT_KHR             = 0x00000200, // = VK_SHADER_STAGE_ANY_HIT_KHR
	CLOSEST_HIT_KHR         = 0x00000400, // = VK_SHADER_STAGE_CLOSEST_HIT_KHR
	MISS_KHR                = 0x00000800, // = VK_SHADER_STAGE_MISS_KHR
	INTERSECTION_KHR        = 0x00001000, // = VK_SHADER_STAGE_INTERSECTION_KHR
	CALLABLE_KHR            = 0x00002000, // = VK_SHADER_STAGE_CALLABLE_KHR
}

DescriptorBinding :: struct {
}

DescriptorSet :: struct {
	set:           u32,
	binding_count: u32,
	bindings:      [^]^DescriptorBinding,
}

InterfaceVariable :: struct {
}

DecorationFlag :: enum Flag {
	NONE                = 0,
	BLOCK               = 1,
	BUFFER_BLOCK        = 2,
	ROW_MAJOR           = 3,
	COLUMN_MAJOR        = 4,
	BUILT_IN            = 5,
	NOPERSPECTIVE       = 6,
	FLAT                = 7,
	NON_WRITABLE        = 8,
	RELAXED_PRECISION   = 9,
	NON_READABLE        = 10,
	PATCH               = 11,
	PER_VERTEX          = 12,
	PER_TASK            = 13,
	WEIGHT_TEXTURE      = 14,
	BLOCK_MATCH_TEXTURE = 15,
}

DecorationFlags :: distinct bit_set[DecorationFlag;Flag]

NumericTraits :: struct {
	scalar:       struct {
		width, signedness: u32,
	},
	vector:       struct {
		component_count: u32,
	},
	matrix_value: struct {
		column_count, row_count, stride: u32, // Measured in bytes
	},
}

ArrayTraits :: struct {
	dims_count:           u32,
	// Each entry is either:
	// - specialization constant dimension
	// - OpTypeRuntimeArray
	// - the array length otherwise
	dims:                 [MAX_ARRAY_DIMS]u32,
	// Stores Ids for dimensions that are specialization constants
	spec_constant_op_ids: [MAX_ARRAY_DIMS]u32,
	stride:               u32, // Measured in bytes
}

VariableFlag :: enum Flag {
	FLAGS_NONE                  = 0,
	FLAGS_UNUSED                = 1,
	// If variable points to a copy of the PhysicalStorageBuffer struct
	FLAGS_PHYSICAL_POINTER_COPY = 2,
}

VariableFlags :: distinct bit_set[VariableFlag;Flag]

BlockVariable :: struct {
	spirv_id:         u32,
	name:             cstring,
	// For Push Constants, this is the lowest offset of all memebers
	offset:           u32, // Measured in bytes
	absolute_offset:  u32, // Measured in bytes
	size:             u32, // Measured in bytes
	padded_size:      u32, // Measured in bytes
	decoration_flags: DecorationFlags,
	numeric:          NumericTraits,
	array:            ArrayTraits,
	flags:            VariableFlags,
	member_count:     u32,
	members:          [^]BlockVariable,
	type_description: ^TypeDescription,
	word_offset:      struct {
		offset: u32,
	},
}

SpecializationConstant :: struct {
}

ModuleFlag :: enum Flag {
	ONE     = 0,
	NO_COPY = 1,
}

ModuleFlags :: distinct bit_set[ModuleFlag;Flag]

TypeDescription :: struct {
}

ShaderModule :: struct {
	generator:                 Generator,
	entry_point_name:          cstring,
	entry_point_id:            u32,
	entry_point_count:         u32,
	entry_points:              [^]EntryPoint,
	source_language:           SourceLanguage,
	source_language_version:   u32,
	source_file:               cstring,
	source_source:             cstring,
	capability_count:          u32,
	capabilities:              [^]Capability,
	spirv_execution_model:     ExecutionModel, // Uses value(s) from first entry point
	shader_stage:              ShaderStageFlag, // Uses value(s) from first entry point
	descriptor_binding_count:  u32, // Uses value(s) from first entry point
	descriptor_bindings:       [^]DescriptorBinding, // Uses value(s) from first entry point
	descriptor_set_count:      u32, // Uses value(s) from first entry point
	descriptor_sets:           [MAX_DESCRIPTOR_SETS]DescriptorSet, // Uses value(s) from first entry point
	input_variable_count:      u32, // Uses value(s) from first entry point
	input_variables:           [^]^InterfaceVariable, // Uses value(s) from first entry point
	output_variable_count:     u32, // Uses value(s) from first entry point
	output_variables:          [^]^InterfaceVariable, // Uses value(s) from first entry point
	interface_variable_count:  u32, // Uses value(s) from first entry point
	interface_variables:       [^]InterfaceVariable, // Uses value(s) from first entry point
	push_constant_block_count: u32, // Uses value(s) from first entry point
	push_constant_blocks:      [^]BlockVariable, // Uses value(s) from first entry point
	spec_constant_count:       u32, // Uses value(s) from first entry point
	spec_constants:            [^]SpecializationConstant, // Uses value(s) from first entry point
	_internal:                 ^struct {
		module_flags:           ModuleFlags,
		spirv_size:             c.size_t,
		spirv_code:             [^]u32,
		spirv_word_count:       u32,
		type_description_count: c.size_t,
		type_descriptions:      [^]TypeDescription,
	},
}

@(default_calling_convention = "c", link_prefix = "spvReflect")
foreign spirv {
	CreateShaderModule :: proc(size: c.size_t, p_code: rawptr, p_module: ^ShaderModule) ---
	DestroyShaderModule :: proc(p_module: ^ShaderModule) ---


	EnumeratePushConstantBlocks :: proc(#by_ptr p_module: ShaderModule, p_count: ^u32, pp_blocks: [^]^BlockVariable) -> Result ---
}
