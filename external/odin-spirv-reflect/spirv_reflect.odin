package spirv_reflect

import "core:c"
import vk "vendor:vulkan"

when ODIN_OS == .Linux {
	foreign import spirv "SPIRV-Reflect/build/libspirv-reflect-static.lib"
} else when ODIN_OS == .Windows {
	foreign import spirv "SPIRV-Reflect/build/Release/spirv-reflect-static.lib"
}


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

SourceLanguage :: enum u32 {
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

ExecutionModel :: enum u32 {
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

ShaderStageFlags :: vk.ShaderStageFlags

DescriptorType :: enum u32 {
  SAMPLER                    =  0,        // = VK_DESCRIPTOR_TYPE_SAMPLER
  COMBINED_IMAGE_SAMPLER     =  1,        // = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
  SAMPLED_IMAGE              =  2,        // = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
  STORAGE_IMAGE              =  3,        // = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE
  UNIFORM_TEXEL_BUFFER       =  4,        // = VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER
  STORAGE_TEXEL_BUFFER       =  5,        // = VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER
  UNIFORM_BUFFER             =  6,        // = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
  STORAGE_BUFFER             =  7,        // = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
  UNIFORM_BUFFER_DYNAMIC     =  8,        // = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC
  STORAGE_BUFFER_DYNAMIC     =  9,        // = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC
  INPUT_ATTACHMENT           = 10,        // = VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT
  ACCELERATION_STRUCTURE_KHR = 1000150000, // = VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR
}

ResourceType :: enum u32 {
  UNDEFINED           = 0x00000000,
  SAMPLER             = 0x00000001,
  CBV                 = 0x00000002,
  SRV                 = 0x00000004,
  UAV                 = 0x00000008,
} 

Dim :: enum u32 {
  _1D = 0,
  _2D = 1,
  _3D = 2,
  Cube = 3,
  Rect = 4,
  Buffer = 5,
  SubpassData = 6,
  TileImageDataEXT = 4173,
  Max = 0x7fffffff,
}

ImageFormat :: enum u32 {
  Unknown = 0,
  Rgba32f = 1,
  Rgba16f = 2,
  R32f = 3,
  Rgba8 = 4,
  Rgba8Snorm = 5,
  Rg32f = 6,
  Rg16f = 7,
  R11fG11fB10f = 8,
  R16f = 9,
  Rgba16 = 10,
  Rgb10A2 = 11,
  Rg16 = 12,
  Rg8 = 13,
  R16 = 14,
  R8 = 15,
  Rgba16Snorm = 16,
  Rg16Snorm = 17,
  Rg8Snorm = 18,
  R16Snorm = 19,
  R8Snorm = 20,
  Rgba32i = 21,
  Rgba16i = 22,
  Rgba8i = 23,
  R32i = 24,
  Rg32i = 25,
  Rg16i = 26,
  Rg8i = 27,
  R16i = 28,
  R8i = 29,
  Rgba32ui = 30,
  Rgba16ui = 31,
  Rgba8ui = 32,
  R32ui = 33,
  Rgb10a2ui = 34,
  Rg32ui = 35,
  Rg16ui = 36,
  Rg8ui = 37,
  R16ui = 38,
  R8ui = 39,
  R64ui = 40,
  R64i = 41,
  Max = 0x7fffffff,
}

ImageTraits :: struct {
	dim: Dim,
	depth, arrayed, ms, sampled: u32,
	image_format: ImageFormat,
} 

// Based of SPV_GOOGLE_user_type
UserType :: enum {
  INVALID = 0,
  CBUFFER,
  TBUFFER,
  APPEND_STRUCTURED_BUFFER,
  BUFFER,
  BYTE_ADDRESS_BUFFER,
  CONSTANT_BUFFER,
  CONSUME_STRUCTURED_BUFFER,
  INPUT_PATCH,
  OUTPUT_PATCH,
  RASTERIZER_ORDERED_BUFFER,
  RASTERIZER_ORDERED_BYTE_ADDRESS_BUFFER,
  RASTERIZER_ORDERED_STRUCTURED_BUFFER,
  RASTERIZER_ORDERED_TEXTURE_1D,
  RASTERIZER_ORDERED_TEXTURE_1D_ARRAY,
  RASTERIZER_ORDERED_TEXTURE_2D,
  RASTERIZER_ORDERED_TEXTURE_2D_ARRAY,
  RASTERIZER_ORDERED_TEXTURE_3D,
  RAYTRACING_ACCELERATION_STRUCTURE,
  RW_BUFFER,
  RW_BYTE_ADDRESS_BUFFER,
  RW_STRUCTURED_BUFFER,
  RW_TEXTURE_1D,
  RW_TEXTURE_1D_ARRAY,
  RW_TEXTURE_2D,
  RW_TEXTURE_2D_ARRAY,
  RW_TEXTURE_3D,
  STRUCTURED_BUFFER,
  SUBPASS_INPUT,
  SUBPASS_INPUT_MS,
  TEXTURE_1D,
  TEXTURE_1D_ARRAY,
  TEXTURE_2D,
  TEXTURE_2D_ARRAY,
  TEXTURE_2DMS,
  TEXTURE_2DMS_ARRAY,
  TEXTURE_3D,
  TEXTURE_BUFFER,
  TEXTURE_CUBE,
  TEXTURE_CUBE_ARRAY,
}

DescriptorBinding :: struct {
	 spirv_id: u32,
	 name: cstring,
	 binding, input_attachment_index, set: u32,
	 descriptor_type: DescriptorType,
	 resource_type: ResourceType,
	 image: ImageTraits,
	 block: BlockVariable,
	 array: BindingArrayTraits,
	 count, accessed, uav_counter_id: u32,
	 uav_counter_binding: ^DescriptorBinding,
	 byte_address_buffer_offset_count: u32,
	 byte_address_buffer_offsets: [^]u32,
	 type_description: ^TypeDescription,
	 word_offset: struct {
		binding, set: u32,
	 },
	 decoration_flags: DecorationFlags,
	 user_type: UserType,
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

BindingArrayTraits :: struct {
	dims_count: u32,
	dims: [MAX_ARRAY_DIMS]u32,
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
	shader_stage:              ShaderStageFlags, // Uses value(s) from first entry point
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
	EnumerateDescriptorSets :: proc(#by_ptr p_module: ShaderModule, p_count: ^u32, pp_sets: [^]^DescriptorSet) -> Result ---
}
