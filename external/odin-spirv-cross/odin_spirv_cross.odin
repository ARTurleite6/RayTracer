package odin_spirv_cross

import "core:c"

foreign import spirv_cross {"lib/spirv-cross-c.lib", "lib/spirv-cross-core.lib", "lib/spirv-cross-glsl.lib"}

spvc_context :: rawptr
parsed_ir :: rawptr
compiler :: rawptr
compiler_options :: rawptr
resources :: rawptr
set :: rawptr
constant :: rawptr

SpvId :: c.uint
variable_id :: SpvId
spvc_type_id :: SpvId
constant_id :: SpvId
type :: rawptr

result :: enum c.int {
	/* Success. */
	SUCCESS                 = 0,

	/* The SPIR-V is invalid. Should have been caught by validation ideally. */
	ERROR_INVALID_SPIRV     = -1,

	/* The SPIR-V might be valid or invalid, but SPIRV-Cross currently cannot correctly translate this to your target language. */
	ERROR_UNSUPPORTED_SPIRV = -2,

	/* If for some reason we hit this, new or malloc failed. */
	ERROR_OUT_OF_MEMORY     = -3,

	/* Invalid API argument. */
	ERROR_INVALID_ARGUMENT  = -4,
	ERROR_INT_MAX           = 0x7fffffff,
}

backend :: enum c.int {
	/* This backend can only perform reflection, no compiler options are supported. Maps to spirv_cross::Compiler. */
	NONE    = 0,
	GLSL    = 1, /* spirv_cross::CompilerGLSL */
	HLSL    = 2, /* CompilerHLSL */
	MSL     = 3, /* CompilerMSL */
	CPP     = 4, /* CompilerCPP */
	JSON    = 5, /* CompilerReflection w/ JSON backend */
	INT_MAX = 0x7fffffff,
}

capture_mode :: enum c.int {
	/* The Parsed IR payload will be copied, and the handle can be reused to create other compiler instances. */
	MODE_COPY      = 0,

	/*
	 * The payload will now be owned by the compiler.
	 * parsed_ir should now be considered a dead blob and must not be used further.
	 * This is optimal for performance and should be the go-to option.
	 */
	TAKE_OWNERSHIP = 1,
	INT_MAX        = 0x7fffffff,
}

COMPILER_OPTION_COMMON_BIT :: 0x1000000
COMPILER_OPTION_GLSL_BIT :: 0x2000000
COMPILER_OPTION_HLSL_BIT :: 0x4000000
COMPILER_OPTION_MSL_BIT :: 0x8000000
COMPILER_OPTION_LANG_BITS :: 0x0f000000
COMPILER_OPTION_ENUM_BITS :: 0xffffff

compiler_option :: enum c.int {
	UNKNOWN                                        = 0,
	FORCE_TEMPORARY                                = 1 | COMPILER_OPTION_COMMON_BIT,
	FLATTEN_MULTIDIMENSIONAL_ARRAYS                = 2 | COMPILER_OPTION_COMMON_BIT,
	FIXUP_DEPTH_CONVENTION                         = 3 | COMPILER_OPTION_COMMON_BIT,
	FLIP_VERTEX_Y                                  = 4 | COMPILER_OPTION_COMMON_BIT,
	GLSL_SUPPORT_NONZERO_BASE_INSTANCE             = 5 | COMPILER_OPTION_GLSL_BIT,
	GLSL_SEPARATE_SHADER_OBJECTS                   = 6 | COMPILER_OPTION_GLSL_BIT,
	GLSL_ENABLE_420PACK_EXTENSION                  = 7 | COMPILER_OPTION_GLSL_BIT,
	GLSL_VERSION                                   = 8 | COMPILER_OPTION_GLSL_BIT,
	GLSL_ES                                        = 9 | COMPILER_OPTION_GLSL_BIT,
	GLSL_VULKAN_SEMANTICS                          = 10 | COMPILER_OPTION_GLSL_BIT,
	GLSL_ES_DEFAULT_FLOAT_PRECISION_HIGHP          = 11 | COMPILER_OPTION_GLSL_BIT,
	GLSL_ES_DEFAULT_INT_PRECISION_HIGHP            = 12 | COMPILER_OPTION_GLSL_BIT,
	HLSL_SHADER_MODEL                              = 13 | COMPILER_OPTION_HLSL_BIT,
	HLSL_POINT_SIZE_COMPAT                         = 14 | COMPILER_OPTION_HLSL_BIT,
	HLSL_POINT_COORD_COMPAT                        = 15 | COMPILER_OPTION_HLSL_BIT,
	HLSL_SUPPORT_NONZERO_BASE_VERTEX_BASE_INSTANCE = 16 | COMPILER_OPTION_HLSL_BIT,
	MSL_VERSION                                    = 17 | COMPILER_OPTION_MSL_BIT,
	MSL_TEXEL_BUFFER_TEXTURE_WIDTH                 = 18 | COMPILER_OPTION_MSL_BIT,

	/* Obsolete, use SWIZZLE_BUFFER_INDEX instead. */
	MSL_AUX_BUFFER_INDEX                           = 19 | COMPILER_OPTION_MSL_BIT,
	MSL_SWIZZLE_BUFFER_INDEX                       = 19 | COMPILER_OPTION_MSL_BIT,
	MSL_INDIRECT_PARAMS_BUFFER_INDEX               = 20 | COMPILER_OPTION_MSL_BIT,
	MSL_SHADER_OUTPUT_BUFFER_INDEX                 = 21 | COMPILER_OPTION_MSL_BIT,
	MSL_SHADER_PATCH_OUTPUT_BUFFER_INDEX           = 22 | COMPILER_OPTION_MSL_BIT,
	MSL_SHADER_TESS_FACTOR_OUTPUT_BUFFER_INDEX     = 23 | COMPILER_OPTION_MSL_BIT,
	MSL_SHADER_INPUT_WORKGROUP_INDEX               = 24 | COMPILER_OPTION_MSL_BIT,
	MSL_ENABLE_POINT_SIZE_BUILTIN                  = 25 | COMPILER_OPTION_MSL_BIT,
	MSL_DISABLE_RASTERIZATION                      = 26 | COMPILER_OPTION_MSL_BIT,
	MSL_CAPTURE_OUTPUT_TO_BUFFER                   = 27 | COMPILER_OPTION_MSL_BIT,
	MSL_SWIZZLE_TEXTURE_SAMPLES                    = 28 | COMPILER_OPTION_MSL_BIT,
	MSL_PAD_FRAGMENT_OUTPUT_COMPONENTS             = 29 | COMPILER_OPTION_MSL_BIT,
	MSL_TESS_DOMAIN_ORIGIN_LOWER_LEFT              = 30 | COMPILER_OPTION_MSL_BIT,
	MSL_PLATFORM                                   = 31 | COMPILER_OPTION_MSL_BIT,
	MSL_ARGUMENT_BUFFERS                           = 32 | COMPILER_OPTION_MSL_BIT,
	GLSL_EMIT_PUSH_CONSTANT_AS_UNIFORM_BUFFER      = 33 | COMPILER_OPTION_GLSL_BIT,
	MSL_TEXTURE_BUFFER_NATIVE                      = 34 | COMPILER_OPTION_MSL_BIT,
	GLSL_EMIT_UNIFORM_BUFFER_AS_PLAIN_UNIFORMS     = 35 | COMPILER_OPTION_GLSL_BIT,
	MSL_BUFFER_SIZE_BUFFER_INDEX                   = 36 | COMPILER_OPTION_MSL_BIT,
	EMIT_LINE_DIRECTIVES                           = 37 | COMPILER_OPTION_COMMON_BIT,
	MSL_MULTIVIEW                                  = 38 | COMPILER_OPTION_MSL_BIT,
	MSL_VIEW_MASK_BUFFER_INDEX                     = 39 | COMPILER_OPTION_MSL_BIT,
	MSL_DEVICE_INDEX                               = 40 | COMPILER_OPTION_MSL_BIT,
	MSL_VIEW_INDEX_FROM_DEVICE_INDEX               = 41 | COMPILER_OPTION_MSL_BIT,
	MSL_DISPATCH_BASE                              = 42 | COMPILER_OPTION_MSL_BIT,
	MSL_DYNAMIC_OFFSETS_BUFFER_INDEX               = 43 | COMPILER_OPTION_MSL_BIT,
	MSL_TEXTURE_1D_AS_2D                           = 44 | COMPILER_OPTION_MSL_BIT,
	MSL_ENABLE_BASE_INDEX_ZERO                     = 45 | COMPILER_OPTION_MSL_BIT,

	/* Obsolete. Use MSL_FRAMEBUFFER_FETCH_SUBPASS instead. */
	MSL_IOS_FRAMEBUFFER_FETCH_SUBPASS              = 46 | COMPILER_OPTION_MSL_BIT,
	MSL_FRAMEBUFFER_FETCH_SUBPASS                  = 46 | COMPILER_OPTION_MSL_BIT,
	MSL_INVARIANT_FP_MATH                          = 47 | COMPILER_OPTION_MSL_BIT,
	MSL_EMULATE_CUBEMAP_ARRAY                      = 48 | COMPILER_OPTION_MSL_BIT,
	MSL_ENABLE_DECORATION_BINDING                  = 49 | COMPILER_OPTION_MSL_BIT,
	MSL_FORCE_ACTIVE_ARGUMENT_BUFFER_RESOURCES     = 50 | COMPILER_OPTION_MSL_BIT,
	MSL_FORCE_NATIVE_ARRAYS                        = 51 | COMPILER_OPTION_MSL_BIT,
	ENABLE_STORAGE_IMAGE_QUALIFIER_DEDUCTION       = 52 | COMPILER_OPTION_COMMON_BIT,
	HLSL_FORCE_STORAGE_BUFFER_AS_UAV               = 53 | COMPILER_OPTION_HLSL_BIT,
	FORCE_ZERO_INITIALIZED_VARIABLES               = 54 | COMPILER_OPTION_COMMON_BIT,
	HLSL_NONWRITABLE_UAV_TEXTURE_AS_SRV            = 55 | COMPILER_OPTION_HLSL_BIT,
	MSL_ENABLE_FRAG_OUTPUT_MASK                    = 56 | COMPILER_OPTION_MSL_BIT,
	MSL_ENABLE_FRAG_DEPTH_BUILTIN                  = 57 | COMPILER_OPTION_MSL_BIT,
	MSL_ENABLE_FRAG_STENCIL_REF_BUILTIN            = 58 | COMPILER_OPTION_MSL_BIT,
	MSL_ENABLE_CLIP_DISTANCE_USER_VARYING          = 59 | COMPILER_OPTION_MSL_BIT,
	HLSL_ENABLE_16BIT_TYPES                        = 60 | COMPILER_OPTION_HLSL_BIT,
	MSL_MULTI_PATCH_WORKGROUP                      = 61 | COMPILER_OPTION_MSL_BIT,
	MSL_SHADER_INPUT_BUFFER_INDEX                  = 62 | COMPILER_OPTION_MSL_BIT,
	MSL_SHADER_INDEX_BUFFER_INDEX                  = 63 | COMPILER_OPTION_MSL_BIT,
	MSL_VERTEX_FOR_TESSELLATION                    = 64 | COMPILER_OPTION_MSL_BIT,
	MSL_VERTEX_INDEX_TYPE                          = 65 | COMPILER_OPTION_MSL_BIT,
	GLSL_FORCE_FLATTENED_IO_BLOCKS                 = 66 | COMPILER_OPTION_GLSL_BIT,
	MSL_MULTIVIEW_LAYERED_RENDERING                = 67 | COMPILER_OPTION_MSL_BIT,
	MSL_ARRAYED_SUBPASS_INPUT                      = 68 | COMPILER_OPTION_MSL_BIT,
	MSL_R32UI_LINEAR_TEXTURE_ALIGNMENT             = 69 | COMPILER_OPTION_MSL_BIT,
	MSL_R32UI_ALIGNMENT_CONSTANT_ID                = 70 | COMPILER_OPTION_MSL_BIT,
	HLSL_FLATTEN_MATRIX_VERTEX_INPUT_SEMANTICS     = 71 | COMPILER_OPTION_HLSL_BIT,
	MSL_IOS_USE_SIMDGROUP_FUNCTIONS                = 72 | COMPILER_OPTION_MSL_BIT,
	MSL_EMULATE_SUBGROUPS                          = 73 | COMPILER_OPTION_MSL_BIT,
	MSL_FIXED_SUBGROUP_SIZE                        = 74 | COMPILER_OPTION_MSL_BIT,
	MSL_FORCE_SAMPLE_RATE_SHADING                  = 75 | COMPILER_OPTION_MSL_BIT,
	MSL_IOS_SUPPORT_BASE_VERTEX_INSTANCE           = 76 | COMPILER_OPTION_MSL_BIT,
	GLSL_OVR_MULTIVIEW_VIEW_COUNT                  = 77 | COMPILER_OPTION_GLSL_BIT,
	RELAX_NAN_CHECKS                               = 78 | COMPILER_OPTION_COMMON_BIT,
	MSL_RAW_BUFFER_TESE_INPUT                      = 79 | COMPILER_OPTION_MSL_BIT,
	MSL_SHADER_PATCH_INPUT_BUFFER_INDEX            = 80 | COMPILER_OPTION_MSL_BIT,
	MSL_MANUAL_HELPER_INVOCATION_UPDATES           = 81 | COMPILER_OPTION_MSL_BIT,
	MSL_CHECK_DISCARDED_FRAG_STORES                = 82 | COMPILER_OPTION_MSL_BIT,
	GLSL_ENABLE_ROW_MAJOR_LOAD_WORKAROUND          = 83 | COMPILER_OPTION_GLSL_BIT,
	MSL_ARGUMENT_BUFFERS_TIER                      = 84 | COMPILER_OPTION_MSL_BIT,
	MSL_SAMPLE_DREF_LOD_ARRAY_AS_GRAD              = 85 | COMPILER_OPTION_MSL_BIT,
	MSL_READWRITE_TEXTURE_FENCES                   = 86 | COMPILER_OPTION_MSL_BIT,
	MSL_REPLACE_RECURSIVE_INPUTS                   = 87 | COMPILER_OPTION_MSL_BIT,
	MSL_AGX_MANUAL_CUBE_GRAD_FIXUP                 = 88 | COMPILER_OPTION_MSL_BIT,
	MSL_FORCE_FRAGMENT_WITH_SIDE_EFFECTS_EXECUTION = 89 | COMPILER_OPTION_MSL_BIT,
	HLSL_USE_ENTRY_POINT_NAME                      = 90 | COMPILER_OPTION_HLSL_BIT,
	HLSL_PRESERVE_STRUCTURED_BUFFERS               = 91 | COMPILER_OPTION_HLSL_BIT,
	MSL_AUTO_DISABLE_RASTERIZATION                 = 92 | COMPILER_OPTION_MSL_BIT,
	MSL_ENABLE_POINT_SIZE_DEFAULT                  = 93 | COMPILER_OPTION_MSL_BIT,
	INT_MAX                                        = 0x7fffffff,
}

SpvDecoration :: enum c.int {
	RelaxedPrecision                            = 0,
	SpecId                                      = 1,
	Block                                       = 2,
	BufferBlock                                 = 3,
	RowMajor                                    = 4,
	ColMajor                                    = 5,
	ArrayStride                                 = 6,
	MatrixStride                                = 7,
	GLSLShared                                  = 8,
	GLSLPacked                                  = 9,
	CPacked                                     = 10,
	BuiltIn                                     = 11,
	NoPerspective                               = 13,
	Flat                                        = 14,
	Patch                                       = 15,
	Centroid                                    = 16,
	Sample                                      = 17,
	Invariant                                   = 18,
	Restrict                                    = 19,
	Aliased                                     = 20,
	Volatile                                    = 21,
	Constant                                    = 22,
	Coherent                                    = 23,
	NonWritable                                 = 24,
	NonReadable                                 = 25,
	Uniform                                     = 26,
	UniformId                                   = 27,
	SaturatedConversion                         = 28,
	Stream                                      = 29,
	Location                                    = 30,
	Component                                   = 31,
	Index                                       = 32,
	Binding                                     = 33,
	DescriptorSet                               = 34,
	Offset                                      = 35,
	XfbBuffer                                   = 36,
	XfbStride                                   = 37,
	FuncParamAttr                               = 38,
	FPRoundingMode                              = 39,
	FPFastMathMode                              = 40,
	LinkageAttributes                           = 41,
	NoContraction                               = 42,
	InputAttachmentIndex                        = 43,
	Alignment                                   = 44,
	MaxByteOffset                               = 45,
	AlignmentId                                 = 46,
	MaxByteOffsetId                             = 47,
	SaturatedToLargestFloat8NormalConversionEXT = 4216,
	NoSignedWrap                                = 4469,
	NoUnsignedWrap                              = 4470,
	WeightTextureQCOM                           = 4487,
	BlockMatchTextureQCOM                       = 4488,
	BlockMatchSamplerQCOM                       = 4499,
	ExplicitInterpAMD                           = 4999,
	NodeSharesPayloadLimitsWithAMDX             = 5019,
	NodeMaxPayloadsAMDX                         = 5020,
	TrackFinishWritingAMDX                      = 5078,
	PayloadNodeNameAMDX                         = 5091,
	PayloadNodeBaseIndexAMDX                    = 5098,
	PayloadNodeSparseArrayAMDX                  = 5099,
	PayloadNodeArraySizeAMDX                    = 5100,
	PayloadDispatchIndirectAMDX                 = 5105,
	OverrideCoverageNV                          = 5248,
	PassthroughNV                               = 5250,
	ViewportRelativeNV                          = 5252,
	SecondaryViewportRelativeNV                 = 5256,
	PerPrimitiveEXT                             = 5271,
	PerPrimitiveNV                              = 5271,
	PerViewNV                                   = 5272,
	PerTaskNV                                   = 5273,
	PerVertexKHR                                = 5285,
	PerVertexNV                                 = 5285,
	NonUniform                                  = 5300,
	NonUniformEXT                               = 5300,
	RestrictPointer                             = 5355,
	RestrictPointerEXT                          = 5355,
	AliasedPointer                              = 5356,
	AliasedPointerEXT                           = 5356,
	HitObjectShaderRecordBufferNV               = 5386,
	BindlessSamplerNV                           = 5398,
	BindlessImageNV                             = 5399,
	BoundSamplerNV                              = 5400,
	BoundImageNV                                = 5401,
	SIMTCallINTEL                               = 5599,
	ReferencedIndirectlyINTEL                   = 5602,
	ClobberINTEL                                = 5607,
	SideEffectsINTEL                            = 5608,
	VectorComputeVariableINTEL                  = 5624,
	FuncParamIOKindINTEL                        = 5625,
	VectorComputeFunctionINTEL                  = 5626,
	StackCallINTEL                              = 5627,
	GlobalVariableOffsetINTEL                   = 5628,
	CounterBuffer                               = 5634,
	HlslCounterBufferGOOGLE                     = 5634,
	HlslSemanticGOOGLE                          = 5635,
	UserSemantic                                = 5635,
	UserTypeGOOGLE                              = 5636,
	FunctionRoundingModeINTEL                   = 5822,
	FunctionDenormModeINTEL                     = 5823,
	RegisterINTEL                               = 5825,
	MemoryINTEL                                 = 5826,
	NumbanksINTEL                               = 5827,
	BankwidthINTEL                              = 5828,
	MaxPrivateCopiesINTEL                       = 5829,
	SinglepumpINTEL                             = 5830,
	DoublepumpINTEL                             = 5831,
	MaxReplicatesINTEL                          = 5832,
	SimpleDualPortINTEL                         = 5833,
	MergeINTEL                                  = 5834,
	BankBitsINTEL                               = 5835,
	ForcePow2DepthINTEL                         = 5836,
	StridesizeINTEL                             = 5883,
	WordsizeINTEL                               = 5884,
	TrueDualPortINTEL                           = 5885,
	BurstCoalesceINTEL                          = 5899,
	CacheSizeINTEL                              = 5900,
	DontStaticallyCoalesceINTEL                 = 5901,
	PrefetchINTEL                               = 5902,
	StallEnableINTEL                            = 5905,
	FuseLoopsInFunctionINTEL                    = 5907,
	MathOpDSPModeINTEL                          = 5909,
	AliasScopeINTEL                             = 5914,
	NoAliasINTEL                                = 5915,
	InitiationIntervalINTEL                     = 5917,
	MaxConcurrencyINTEL                         = 5918,
	PipelineEnableINTEL                         = 5919,
	BufferLocationINTEL                         = 5921,
	IOPipeStorageINTEL                          = 5944,
	FunctionFloatingPointModeINTEL              = 6080,
	SingleElementVectorINTEL                    = 6085,
	VectorComputeCallableFunctionINTEL          = 6087,
	MediaBlockIOINTEL                           = 6140,
	StallFreeINTEL                              = 6151,
	FPMaxErrorDecorationINTEL                   = 6170,
	LatencyControlLabelINTEL                    = 6172,
	LatencyControlConstraintINTEL               = 6173,
	ConduitKernelArgumentINTEL                  = 6175,
	RegisterMapKernelArgumentINTEL              = 6176,
	MMHostInterfaceAddressWidthINTEL            = 6177,
	MMHostInterfaceDataWidthINTEL               = 6178,
	MMHostInterfaceLatencyINTEL                 = 6179,
	MMHostInterfaceReadWriteModeINTEL           = 6180,
	MMHostInterfaceMaxBurstINTEL                = 6181,
	MMHostInterfaceWaitRequestINTEL             = 6182,
	StableKernelArgumentINTEL                   = 6183,
	HostAccessINTEL                             = 6188,
	InitModeINTEL                               = 6190,
	ImplementInRegisterMapINTEL                 = 6191,
	CacheControlLoadINTEL                       = 6442,
	CacheControlStoreINTEL                      = 6443,
	Max                                         = 0x7fffffff,
}

SpvBuiltIn :: enum c.int {
	Position                             = 0,
	PointSize                            = 1,
	ClipDistance                         = 3,
	CullDistance                         = 4,
	VertexId                             = 5,
	InstanceId                           = 6,
	PrimitiveId                          = 7,
	InvocationId                         = 8,
	Layer                                = 9,
	ViewportIndex                        = 10,
	TessLevelOuter                       = 11,
	TessLevelInner                       = 12,
	TessCoord                            = 13,
	PatchVertices                        = 14,
	FragCoord                            = 15,
	PointCoord                           = 16,
	FrontFacing                          = 17,
	SampleId                             = 18,
	SamplePosition                       = 19,
	SampleMask                           = 20,
	FragDepth                            = 22,
	HelperInvocation                     = 23,
	NumWorkgroups                        = 24,
	WorkgroupSize                        = 25,
	WorkgroupId                          = 26,
	LocalInvocationId                    = 27,
	GlobalInvocationId                   = 28,
	LocalInvocationIndex                 = 29,
	WorkDim                              = 30,
	GlobalSize                           = 31,
	EnqueuedWorkgroupSize                = 32,
	GlobalOffset                         = 33,
	GlobalLinearId                       = 34,
	SubgroupSize                         = 36,
	SubgroupMaxSize                      = 37,
	NumSubgroups                         = 38,
	NumEnqueuedSubgroups                 = 39,
	SubgroupId                           = 40,
	SubgroupLocalInvocationId            = 41,
	VertexIndex                          = 42,
	InstanceIndex                        = 43,
	CoreIDARM                            = 4160,
	CoreCountARM                         = 4161,
	CoreMaxIDARM                         = 4162,
	WarpIDARM                            = 4163,
	WarpMaxIDARM                         = 4164,
	SubgroupEqMask                       = 4416,
	SubgroupEqMaskKHR                    = 4416,
	SubgroupGeMask                       = 4417,
	SubgroupGeMaskKHR                    = 4417,
	SubgroupGtMask                       = 4418,
	SubgroupGtMaskKHR                    = 4418,
	SubgroupLeMask                       = 4419,
	SubgroupLeMaskKHR                    = 4419,
	SubgroupLtMask                       = 4420,
	SubgroupLtMaskKHR                    = 4420,
	BaseVertex                           = 4424,
	BaseInstance                         = 4425,
	DrawIndex                            = 4426,
	PrimitiveShadingRateKHR              = 4432,
	DeviceIndex                          = 4438,
	ViewIndex                            = 4440,
	ShadingRateKHR                       = 4444,
	TileOffsetQCOM                       = 4492,
	TileDimensionQCOM                    = 4493,
	TileApronSizeQCOM                    = 4494,
	BaryCoordNoPerspAMD                  = 4992,
	BaryCoordNoPerspCentroidAMD          = 4993,
	BaryCoordNoPerspSampleAMD            = 4994,
	BaryCoordSmoothAMD                   = 4995,
	BaryCoordSmoothCentroidAMD           = 4996,
	BaryCoordSmoothSampleAMD             = 4997,
	BaryCoordPullModelAMD                = 4998,
	FragStencilRefEXT                    = 5014,
	RemainingRecursionLevelsAMDX         = 5021,
	ShaderIndexAMDX                      = 5073,
	ViewportMaskNV                       = 5253,
	SecondaryPositionNV                  = 5257,
	SecondaryViewportMaskNV              = 5258,
	PositionPerViewNV                    = 5261,
	ViewportMaskPerViewNV                = 5262,
	FullyCoveredEXT                      = 5264,
	TaskCountNV                          = 5274,
	PrimitiveCountNV                     = 5275,
	PrimitiveIndicesNV                   = 5276,
	ClipDistancePerViewNV                = 5277,
	CullDistancePerViewNV                = 5278,
	LayerPerViewNV                       = 5279,
	MeshViewCountNV                      = 5280,
	MeshViewIndicesNV                    = 5281,
	BaryCoordKHR                         = 5286,
	BaryCoordNV                          = 5286,
	BaryCoordNoPerspKHR                  = 5287,
	BaryCoordNoPerspNV                   = 5287,
	FragSizeEXT                          = 5292,
	FragmentSizeNV                       = 5292,
	FragInvocationCountEXT               = 5293,
	InvocationsPerPixelNV                = 5293,
	PrimitivePointIndicesEXT             = 5294,
	PrimitiveLineIndicesEXT              = 5295,
	PrimitiveTriangleIndicesEXT          = 5296,
	CullPrimitiveEXT                     = 5299,
	LaunchIdKHR                          = 5319,
	LaunchIdNV                           = 5319,
	LaunchSizeKHR                        = 5320,
	LaunchSizeNV                         = 5320,
	WorldRayOriginKHR                    = 5321,
	WorldRayOriginNV                     = 5321,
	WorldRayDirectionKHR                 = 5322,
	WorldRayDirectionNV                  = 5322,
	ObjectRayOriginKHR                   = 5323,
	ObjectRayOriginNV                    = 5323,
	ObjectRayDirectionKHR                = 5324,
	ObjectRayDirectionNV                 = 5324,
	RayTminKHR                           = 5325,
	RayTminNV                            = 5325,
	RayTmaxKHR                           = 5326,
	RayTmaxNV                            = 5326,
	InstanceCustomIndexKHR               = 5327,
	InstanceCustomIndexNV                = 5327,
	ObjectToWorldKHR                     = 5330,
	ObjectToWorldNV                      = 5330,
	WorldToObjectKHR                     = 5331,
	WorldToObjectNV                      = 5331,
	HitTNV                               = 5332,
	HitKindKHR                           = 5333,
	HitKindNV                            = 5333,
	CurrentRayTimeNV                     = 5334,
	HitTriangleVertexPositionsKHR        = 5335,
	HitMicroTriangleVertexPositionsNV    = 5337,
	HitMicroTriangleVertexBarycentricsNV = 5344,
	IncomingRayFlagsKHR                  = 5351,
	IncomingRayFlagsNV                   = 5351,
	RayGeometryIndexKHR                  = 5352,
	HitIsSphereNV                        = 5359,
	HitIsLSSNV                           = 5360,
	HitSpherePositionNV                  = 5361,
	WarpsPerSMNV                         = 5374,
	SMCountNV                            = 5375,
	WarpIDNV                             = 5376,
	SMIDNV                               = 5377,
	HitLSSPositionsNV                    = 5396,
	HitKindFrontFacingMicroTriangleNV    = 5405,
	HitKindBackFacingMicroTriangleNV     = 5406,
	HitSphereRadiusNV                    = 5420,
	HitLSSRadiiNV                        = 5421,
	ClusterIDNV                          = 5436,
	CullMaskKHR                          = 6021,
	Max                                  = 0x7fffffff,
}

resource_type :: enum c.int {
	UNKNOWN                = 0,
	UNIFORM_BUFFER         = 1,
	STORAGE_BUFFER         = 2,
	STAGE_INPUT            = 3,
	STAGE_OUTPUT           = 4,
	SUBPASS_INPUT          = 5,
	STORAGE_IMAGE          = 6,
	SAMPLED_IMAGE          = 7,
	ATOMIC_COUNTER         = 8,
	PUSH_CONSTANT          = 9,
	SEPARATE_IMAGE         = 10,
	SEPARATE_SAMPLERS      = 11,
	ACCELERATION_STRUCTURE = 12,
	RAY_QUERY              = 13,
	SHADER_RECORD_BUFFER   = 14,
	GL_PLAIN_UNIFORM       = 15,
	TENSOR                 = 16,
	INT_MAX                = 0x7fffffff,
}

SpvExecutionModel :: enum c.int {
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

SpvExecutionMode :: enum c.int {
	Invocations                         = 0,
	SpacingEqual                        = 1,
	SpacingFractionalEven               = 2,
	SpacingFractionalOdd                = 3,
	VertexOrderCw                       = 4,
	VertexOrderCcw                      = 5,
	PixelCenterInteger                  = 6,
	OriginUpperLeft                     = 7,
	OriginLowerLeft                     = 8,
	EarlyFragmentTests                  = 9,
	PointMode                           = 10,
	Xfb                                 = 11,
	DepthReplacing                      = 12,
	DepthGreater                        = 14,
	DepthLess                           = 15,
	DepthUnchanged                      = 16,
	LocalSize                           = 17,
	LocalSizeHint                       = 18,
	InputPoints                         = 19,
	InputLines                          = 20,
	InputLinesAdjacency                 = 21,
	Triangles                           = 22,
	InputTrianglesAdjacency             = 23,
	Quads                               = 24,
	Isolines                            = 25,
	OutputVertices                      = 26,
	OutputPoints                        = 27,
	OutputLineStrip                     = 28,
	OutputTriangleStrip                 = 29,
	VecTypeHint                         = 30,
	ContractionOff                      = 31,
	Initializer                         = 33,
	Finalizer                           = 34,
	SubgroupSize                        = 35,
	SubgroupsPerWorkgroup               = 36,
	SubgroupsPerWorkgroupId             = 37,
	LocalSizeId                         = 38,
	LocalSizeHintId                     = 39,
	NonCoherentColorAttachmentReadEXT   = 4169,
	NonCoherentDepthAttachmentReadEXT   = 4170,
	NonCoherentStencilAttachmentReadEXT = 4171,
	SubgroupUniformControlFlowKHR       = 4421,
	PostDepthCoverage                   = 4446,
	DenormPreserve                      = 4459,
	DenormFlushToZero                   = 4460,
	SignedZeroInfNanPreserve            = 4461,
	RoundingModeRTE                     = 4462,
	RoundingModeRTZ                     = 4463,
	NonCoherentTileAttachmentReadQCOM   = 4489,
	TileShadingRateQCOM                 = 4490,
	EarlyAndLateFragmentTestsAMD        = 5017,
	StencilRefReplacingEXT              = 5027,
	CoalescingAMDX                      = 5069,
	IsApiEntryAMDX                      = 5070,
	MaxNodeRecursionAMDX                = 5071,
	StaticNumWorkgroupsAMDX             = 5072,
	ShaderIndexAMDX                     = 5073,
	MaxNumWorkgroupsAMDX                = 5077,
	StencilRefUnchangedFrontAMD         = 5079,
	StencilRefGreaterFrontAMD           = 5080,
	StencilRefLessFrontAMD              = 5081,
	StencilRefUnchangedBackAMD          = 5082,
	StencilRefGreaterBackAMD            = 5083,
	StencilRefLessBackAMD               = 5084,
	QuadDerivativesKHR                  = 5088,
	RequireFullQuadsKHR                 = 5089,
	SharesInputWithAMDX                 = 5102,
	OutputLinesEXT                      = 5269,
	OutputLinesNV                       = 5269,
	OutputPrimitivesEXT                 = 5270,
	OutputPrimitivesNV                  = 5270,
	DerivativeGroupQuadsKHR             = 5289,
	DerivativeGroupQuadsNV              = 5289,
	DerivativeGroupLinearKHR            = 5290,
	DerivativeGroupLinearNV             = 5290,
	OutputTrianglesEXT                  = 5298,
	OutputTrianglesNV                   = 5298,
	PixelInterlockOrderedEXT            = 5366,
	PixelInterlockUnorderedEXT          = 5367,
	SampleInterlockOrderedEXT           = 5368,
	SampleInterlockUnorderedEXT         = 5369,
	ShadingRateInterlockOrderedEXT      = 5370,
	ShadingRateInterlockUnorderedEXT    = 5371,
	SharedLocalMemorySizeINTEL          = 5618,
	RoundingModeRTPINTEL                = 5620,
	RoundingModeRTNINTEL                = 5621,
	FloatingPointModeALTINTEL           = 5622,
	FloatingPointModeIEEEINTEL          = 5623,
	MaxWorkgroupSizeINTEL               = 5893,
	MaxWorkDimINTEL                     = 5894,
	NoGlobalOffsetINTEL                 = 5895,
	NumSIMDWorkitemsINTEL               = 5896,
	SchedulerTargetFmaxMhzINTEL         = 5903,
	MaximallyReconvergesKHR             = 6023,
	FPFastMathDefault                   = 6028,
	StreamingInterfaceINTEL             = 6154,
	RegisterMapInterfaceINTEL           = 6160,
	NamedBarrierCountINTEL              = 6417,
	MaximumRegistersINTEL               = 6461,
	MaximumRegistersIdINTEL             = 6462,
	NamedMaximumRegistersINTEL          = 6463,
	Max                                 = 0x7fffffff,
}

SpvStorageClass :: enum c.int {
	UniformConstant          = 0,
	Input                    = 1,
	Uniform                  = 2,
	Output                   = 3,
	Workgroup                = 4,
	CrossWorkgroup           = 5,
	Private                  = 6,
	Function                 = 7,
	Generic                  = 8,
	PushConstant             = 9,
	AtomicCounter            = 10,
	Image                    = 11,
	StorageBuffer            = 12,
	TileImageEXT             = 4172,
	TileAttachmentQCOM       = 4491,
	NodePayloadAMDX          = 5068,
	CallableDataKHR          = 5328,
	CallableDataNV           = 5328,
	IncomingCallableDataKHR  = 5329,
	IncomingCallableDataNV   = 5329,
	RayPayloadKHR            = 5338,
	RayPayloadNV             = 5338,
	HitAttributeKHR          = 5339,
	HitAttributeNV           = 5339,
	IncomingRayPayloadKHR    = 5342,
	IncomingRayPayloadNV     = 5342,
	ShaderRecordBufferKHR    = 5343,
	ShaderRecordBufferNV     = 5343,
	PhysicalStorageBuffer    = 5349,
	PhysicalStorageBufferEXT = 5349,
	HitObjectAttributeNV     = 5385,
	TaskPayloadWorkgroupEXT  = 5402,
	CodeSectionINTEL         = 5605,
	DeviceOnlyINTEL          = 5936,
	HostOnlyINTEL            = 5937,
	Max                      = 0x7fffffff,
}

basetype :: enum c.int {
	UNKNOWN                = 0,
	VOID                   = 1,
	BOOLEAN                = 2,
	INT8                   = 3,
	UINT8                  = 4,
	INT16                  = 5,
	UINT16                 = 6,
	INT32                  = 7,
	UINT32                 = 8,
	INT64                  = 9,
	UINT64                 = 10,
	ATOMIC_COUNTER         = 11,
	FP16                   = 12,
	FP32                   = 13,
	FP64                   = 14,
	STRUCT                 = 15,
	IMAGE                  = 16,
	SAMPLED_IMAGE          = 17,
	SAMPLER                = 18,
	ACCELERATION_STRUCTURE = 19,
	INT_MAX                = 0x7fffffff,
}

SpvDim :: enum c.int {
	_1D              = 0,
	_2D              = 1,
	_3D              = 2,
	Cube             = 3,
	Rect             = 4,
	Buffer           = 5,
	SubpassData      = 6,
	TileImageDataEXT = 4173,
	Max              = 0x7fffffff,
}

SpvImageFormat :: enum c.int {
	Unknown      = 0,
	Rgba32f      = 1,
	Rgba16f      = 2,
	R32f         = 3,
	Rgba8        = 4,
	Rgba8Snorm   = 5,
	Rg32f        = 6,
	Rg16f        = 7,
	R11fG11fB10f = 8,
	R16f         = 9,
	Rgba16       = 10,
	Rgb10A2      = 11,
	Rg16         = 12,
	Rg8          = 13,
	R16          = 14,
	R8           = 15,
	Rgba16Snorm  = 16,
	Rg16Snorm    = 17,
	Rg8Snorm     = 18,
	R16Snorm     = 19,
	R8Snorm      = 20,
	Rgba32i      = 21,
	Rgba16i      = 22,
	Rgba8i       = 23,
	R32i         = 24,
	Rg32i        = 25,
	Rg16i        = 26,
	Rg8i         = 27,
	R16i         = 28,
	R8i          = 29,
	Rgba32ui     = 30,
	Rgba16ui     = 31,
	Rgba8ui      = 32,
	R32ui        = 33,
	Rgb10a2ui    = 34,
	Rg32ui       = 35,
	Rg16ui       = 36,
	Rg8ui        = 37,
	R16ui        = 38,
	R8ui         = 39,
	R64ui        = 40,
	R64i         = 41,
	Max          = 0x7fffffff,
}

SpvAccessQualifier :: enum c.int {
	ReadOnly  = 0,
	WriteOnly = 1,
	ReadWrite = 2,
	Max       = 0x7fffffff,
}

SpvCapability :: enum c.int {
	Matrix                                       = 0,
	Shader                                       = 1,
	Geometry                                     = 2,
	Tessellation                                 = 3,
	Addresses                                    = 4,
	Linkage                                      = 5,
	Kernel                                       = 6,
	Vector16                                     = 7,
	Float16Buffer                                = 8,
	Float16                                      = 9,
	Float64                                      = 10,
	Int64                                        = 11,
	Int64Atomics                                 = 12,
	ImageBasic                                   = 13,
	ImageReadWrite                               = 14,
	ImageMipmap                                  = 15,
	Pipes                                        = 17,
	Groups                                       = 18,
	DeviceEnqueue                                = 19,
	LiteralSampler                               = 20,
	AtomicStorage                                = 21,
	Int16                                        = 22,
	TessellationPointSize                        = 23,
	GeometryPointSize                            = 24,
	ImageGatherExtended                          = 25,
	StorageImageMultisample                      = 27,
	UniformBufferArrayDynamicIndexing            = 28,
	SampledImageArrayDynamicIndexing             = 29,
	StorageBufferArrayDynamicIndexing            = 30,
	StorageImageArrayDynamicIndexing             = 31,
	ClipDistance                                 = 32,
	CullDistance                                 = 33,
	ImageCubeArray                               = 34,
	SampleRateShading                            = 35,
	ImageRect                                    = 36,
	SampledRect                                  = 37,
	GenericPointer                               = 38,
	Int8                                         = 39,
	InputAttachment                              = 40,
	SparseResidency                              = 41,
	MinLod                                       = 42,
	Sampled1D                                    = 43,
	Image1D                                      = 44,
	SampledCubeArray                             = 45,
	SampledBuffer                                = 46,
	ImageBuffer                                  = 47,
	ImageMSArray                                 = 48,
	StorageImageExtendedFormats                  = 49,
	ImageQuery                                   = 50,
	DerivativeControl                            = 51,
	InterpolationFunction                        = 52,
	TransformFeedback                            = 53,
	GeometryStreams                              = 54,
	StorageImageReadWithoutFormat                = 55,
	StorageImageWriteWithoutFormat               = 56,
	MultiViewport                                = 57,
	SubgroupDispatch                             = 58,
	NamedBarrier                                 = 59,
	PipeStorage                                  = 60,
	GroupNonUniform                              = 61,
	GroupNonUniformVote                          = 62,
	GroupNonUniformArithmetic                    = 63,
	GroupNonUniformBallot                        = 64,
	GroupNonUniformShuffle                       = 65,
	GroupNonUniformShuffleRelative               = 66,
	GroupNonUniformClustered                     = 67,
	GroupNonUniformQuad                          = 68,
	ShaderLayer                                  = 69,
	ShaderViewportIndex                          = 70,
	UniformDecoration                            = 71,
	CoreBuiltinsARM                              = 4165,
	TileImageColorReadAccessEXT                  = 4166,
	TileImageDepthReadAccessEXT                  = 4167,
	TileImageStencilReadAccessEXT                = 4168,
	FragmentShadingRateKHR                       = 4422,
	SubgroupBallotKHR                            = 4423,
	DrawParameters                               = 4427,
	WorkgroupMemoryExplicitLayoutKHR             = 4428,
	WorkgroupMemoryExplicitLayout8BitAccessKHR   = 4429,
	WorkgroupMemoryExplicitLayout16BitAccessKHR  = 4430,
	SubgroupVoteKHR                              = 4431,
	StorageBuffer16BitAccess                     = 4433,
	StorageUniformBufferBlock16                  = 4433,
	StorageUniform16                             = 4434,
	UniformAndStorageBuffer16BitAccess           = 4434,
	StoragePushConstant16                        = 4435,
	StorageInputOutput16                         = 4436,
	DeviceGroup                                  = 4437,
	MultiView                                    = 4439,
	VariablePointersStorageBuffer                = 4441,
	VariablePointers                             = 4442,
	AtomicStorageOps                             = 4445,
	SampleMaskPostDepthCoverage                  = 4447,
	StorageBuffer8BitAccess                      = 4448,
	UniformAndStorageBuffer8BitAccess            = 4449,
	StoragePushConstant8                         = 4450,
	DenormPreserve                               = 4464,
	DenormFlushToZero                            = 4465,
	SignedZeroInfNanPreserve                     = 4466,
	RoundingModeRTE                              = 4467,
	RoundingModeRTZ                              = 4468,
	RayQueryProvisionalKHR                       = 4471,
	RayQueryKHR                                  = 4472,
	RayTraversalPrimitiveCullingKHR              = 4478,
	RayTracingKHR                                = 4479,
	TextureSampleWeightedQCOM                    = 4484,
	TextureBoxFilterQCOM                         = 4485,
	TextureBlockMatchQCOM                        = 4486,
	Float16ImageAMD                              = 5008,
	ImageGatherBiasLodAMD                        = 5009,
	FragmentMaskAMD                              = 5010,
	StencilExportEXT                             = 5013,
	ImageReadWriteLodAMD                         = 5015,
	Int64ImageEXT                                = 5016,
	ShaderClockKHR                               = 5055,
	SampleMaskOverrideCoverageNV                 = 5249,
	GeometryShaderPassthroughNV                  = 5251,
	ShaderViewportIndexLayerEXT                  = 5254,
	ShaderViewportIndexLayerNV                   = 5254,
	ShaderViewportMaskNV                         = 5255,
	ShaderStereoViewNV                           = 5259,
	PerViewAttributesNV                          = 5260,
	FragmentFullyCoveredEXT                      = 5265,
	MeshShadingNV                                = 5266,
	ImageFootprintNV                             = 5282,
	MeshShadingEXT                               = 5283,
	FragmentBarycentricKHR                       = 5284,
	FragmentBarycentricNV                        = 5284,
	ComputeDerivativeGroupQuadsNV                = 5288,
	FragmentDensityEXT                           = 5291,
	ShadingRateNV                                = 5291,
	GroupNonUniformPartitionedNV                 = 5297,
	ShaderNonUniform                             = 5301,
	ShaderNonUniformEXT                          = 5301,
	RuntimeDescriptorArray                       = 5302,
	RuntimeDescriptorArrayEXT                    = 5302,
	InputAttachmentArrayDynamicIndexing          = 5303,
	InputAttachmentArrayDynamicIndexingEXT       = 5303,
	UniformTexelBufferArrayDynamicIndexing       = 5304,
	UniformTexelBufferArrayDynamicIndexingEXT    = 5304,
	StorageTexelBufferArrayDynamicIndexing       = 5305,
	StorageTexelBufferArrayDynamicIndexingEXT    = 5305,
	UniformBufferArrayNonUniformIndexing         = 5306,
	UniformBufferArrayNonUniformIndexingEXT      = 5306,
	SampledImageArrayNonUniformIndexing          = 5307,
	SampledImageArrayNonUniformIndexingEXT       = 5307,
	StorageBufferArrayNonUniformIndexing         = 5308,
	StorageBufferArrayNonUniformIndexingEXT      = 5308,
	StorageImageArrayNonUniformIndexing          = 5309,
	StorageImageArrayNonUniformIndexingEXT       = 5309,
	InputAttachmentArrayNonUniformIndexing       = 5310,
	InputAttachmentArrayNonUniformIndexingEXT    = 5310,
	UniformTexelBufferArrayNonUniformIndexing    = 5311,
	UniformTexelBufferArrayNonUniformIndexingEXT = 5311,
	StorageTexelBufferArrayNonUniformIndexing    = 5312,
	StorageTexelBufferArrayNonUniformIndexingEXT = 5312,
	RayTracingPositionFetchKHR                   = 5336,
	RayTracingNV                                 = 5340,
	RayTracingMotionBlurNV                       = 5341,
	VulkanMemoryModel                            = 5345,
	VulkanMemoryModelKHR                         = 5345,
	VulkanMemoryModelDeviceScope                 = 5346,
	VulkanMemoryModelDeviceScopeKHR              = 5346,
	PhysicalStorageBufferAddresses               = 5347,
	PhysicalStorageBufferAddressesEXT            = 5347,
	ComputeDerivativeGroupLinearNV               = 5350,
	RayTracingProvisionalKHR                     = 5353,
	CooperativeMatrixNV                          = 5357,
	FragmentShaderSampleInterlockEXT             = 5363,
	FragmentShaderShadingRateInterlockEXT        = 5372,
	ShaderSMBuiltinsNV                           = 5373,
	FragmentShaderPixelInterlockEXT              = 5378,
	DemoteToHelperInvocation                     = 5379,
	DemoteToHelperInvocationEXT                  = 5379,
	RayTracingOpacityMicromapEXT                 = 5381,
	ShaderInvocationReorderNV                    = 5383,
	BindlessTextureNV                            = 5390,
	RayQueryPositionFetchKHR                     = 5391,
	SubgroupShuffleINTEL                         = 5568,
	SubgroupBufferBlockIOINTEL                   = 5569,
	SubgroupImageBlockIOINTEL                    = 5570,
	SubgroupImageMediaBlockIOINTEL               = 5579,
	RoundToInfinityINTEL                         = 5582,
	FloatingPointModeINTEL                       = 5583,
	IntegerFunctions2INTEL                       = 5584,
	FunctionPointersINTEL                        = 5603,
	IndirectReferencesINTEL                      = 5604,
	AsmINTEL                                     = 5606,
	AtomicFloat32MinMaxEXT                       = 5612,
	AtomicFloat64MinMaxEXT                       = 5613,
	AtomicFloat16MinMaxEXT                       = 5616,
	VectorComputeINTEL                           = 5617,
	VectorAnyINTEL                               = 5619,
	ExpectAssumeKHR                              = 5629,
	SubgroupAvcMotionEstimationINTEL             = 5696,
	SubgroupAvcMotionEstimationIntraINTEL        = 5697,
	SubgroupAvcMotionEstimationChromaINTEL       = 5698,
	VariableLengthArrayINTEL                     = 5817,
	FunctionFloatControlINTEL                    = 5821,
	FPGAMemoryAttributesINTEL                    = 5824,
	FPFastMathModeINTEL                          = 5837,
	ArbitraryPrecisionIntegersINTEL              = 5844,
	ArbitraryPrecisionFloatingPointINTEL         = 5845,
	UnstructuredLoopControlsINTEL                = 5886,
	FPGALoopControlsINTEL                        = 5888,
	KernelAttributesINTEL                        = 5892,
	FPGAKernelAttributesINTEL                    = 5897,
	FPGAMemoryAccessesINTEL                      = 5898,
	FPGAClusterAttributesINTEL                   = 5904,
	LoopFuseINTEL                                = 5906,
	FPGADSPControlINTEL                          = 5908,
	MemoryAccessAliasingINTEL                    = 5910,
	FPGAInvocationPipeliningAttributesINTEL      = 5916,
	FPGABufferLocationINTEL                      = 5920,
	ArbitraryPrecisionFixedPointINTEL            = 5922,
	USMStorageClassesINTEL                       = 5935,
	RuntimeAlignedAttributeINTEL                 = 5939,
	IOPipesINTEL                                 = 5943,
	BlockingPipesINTEL                           = 5945,
	FPGARegINTEL                                 = 5948,
	DotProductInputAll                           = 6016,
	DotProductInputAllKHR                        = 6016,
	DotProductInput4x8Bit                        = 6017,
	DotProductInput4x8BitKHR                     = 6017,
	DotProductInput4x8BitPacked                  = 6018,
	DotProductInput4x8BitPackedKHR               = 6018,
	DotProduct                                   = 6019,
	DotProductKHR                                = 6019,
	RayCullMaskKHR                               = 6020,
	CooperativeMatrixKHR                         = 6022,
	BitInstructions                              = 6025,
	GroupNonUniformRotateKHR                     = 6026,
	AtomicFloat32AddEXT                          = 6033,
	AtomicFloat64AddEXT                          = 6034,
	LongConstantCompositeINTEL                   = 6089,
	OptNoneINTEL                                 = 6094,
	AtomicFloat16AddEXT                          = 6095,
	DebugInfoModuleINTEL                         = 6114,
	BFloat16ConversionINTEL                      = 6115,
	SplitBarrierINTEL                            = 6141,
	FPGAKernelAttributesv2INTEL                  = 6161,
	FPGALatencyControlINTEL                      = 6171,
	FPGAArgumentInterfacesINTEL                  = 6174,
	GroupUniformArithmeticKHR                    = 6400,
	Max                                          = 0x7fffffff,
}

reflected_resource :: struct {
	id:                    variable_id,
	base_type_id, type_id: spvc_type_id,
	name:                  cstring,
}

reflected_builtin_resource :: struct {
	builtin:       SpvBuiltIn,
	value_type_id: spvc_type_id,
	resource:      reflected_resource,
}

entry_point :: struct {
	execution_model: SpvExecutionModel,
	name:            cstring,
}


combined_image_sampler :: struct {
	combined_id, image_id, sampler_id: variable_id,
}

/* See C++ API. */
specialization_constant :: struct {
	id:          constant_id,
	constant_id: c.uint,
}

/* See C++ API. */
buffer_range :: struct {
	index:  c.uint,
	offset: c.size_t,
	range:  c.size_t,
}

error_callback :: #type proc(userdata: rawptr, error: cstring)

@(default_calling_convention = "c", link_prefix = "spvc_")
foreign spirv_cross {
	// Context
	context_create :: proc(ctx: ^spvc_context) -> result ---
	context_destroy :: proc(ctx: spvc_context) ---
	context_release_allocations :: proc(ctx: spvc_context) ---
	context_get_last_error_string :: proc(ctx: spvc_context) -> cstring ---
	context_set_error_callback :: proc(ctx: spvc_context, cb: error_callback, userdata: rawptr) ---
	context_parse_spirv :: proc(ctx: spvc_context, spirv: [^]SpvId, word_count: c.size_t, parsed_ir: ^parsed_ir) -> result ---

	// Compiler
	context_create_compiler :: proc(ctx: spvc_context, backend: backend, parsed_ir: parsed_ir, mode: capture_mode, compiler: ^compiler) -> result ---
	compiler_get_current_id_bound :: proc(compiler: compiler) -> c.uint ---
	compiler_create_compiler_options :: proc(compiler: compiler, options: ^compiler_options) -> result ---
	compiler_options_set_bool :: proc(options: compiler_options, option: compiler_option, value: bool) -> result ---
	compiler_options_set_uint :: proc(options: compiler_options, option: compiler_option, value: c.uint) -> result ---
	compiler_install_compiler_options :: proc(compiler: compiler, options: compiler_options) -> result ---
	compiler_compile :: proc(compiler: compiler, source: cstring) -> result ---

	compiler_add_header_line :: proc(compiler: compiler, line: cstring) -> result ---
	compiler_require_extension :: proc(compiler: compiler, extension: cstring) -> result ---
	compiler_get_num_required_extensions :: proc(compiler: compiler) -> c.size_t ---
	compiler_get_required_extension :: proc(compiler: compiler, index: c.size_t) -> cstring ---
	compiler_flatten_buffer_block :: proc(compiler: compiler, id: variable_id) -> result ---
	compiler_variable_is_depth_or_compare :: proc(compiler: compiler, id: variable_id) -> bool ---
	compiler_mask_stage_output_by_location :: proc(compiler: compiler, location, component: c.uint) -> result ---
	compiler_mask_stage_output_by_builtin :: proc(compiler: compiler, builtin: SpvBuiltIn) -> result ---

	// Reflect resources
	compiler_get_active_interface_variables :: proc(compiler: compiler, set: ^set) -> result ---
	compiler_set_enabled_interface_variables :: proc(compiler: compiler, set: set) -> result ---
	compiler_create_shader_resources :: proc(compiler: compiler, resources: ^resources) -> result ---
	resources_get_resource_list_for_type :: proc(resources: resources, type: resource_type, resource_list: ^[^]reflected_resource, size: ^c.size_t) -> result ---
	resources_get_builtin_resource_list_for_type :: proc(resources: resources, type: resource_type, resource_list: ^[^]reflected_builtin_resource, resource_size: ^c.size_t) -> result ---

	// Decorations

	compiler_set_decoration :: proc(compiler: compiler, id: SpvId, decoration: SpvDecoration, argument: c.uint) ---
	compiler_set_decoration_string :: proc(compiler: compiler, id: SpvId, decoration: SpvDecoration, argument: cstring) ---
	compiler_set_name :: proc(compiler: compiler, id: SpvId, argument: cstring) ---
	compiler_set_member_decoration :: proc(compiler: compiler, id: spvc_type_id, member_index: c.uint, decoration: SpvDecoration, argument: c.uint) ---
	compiler_set_member_decoration_string :: proc(compiler: compiler, id: spvc_type_id, member_index: c.uint, decoration: SpvDecoration, argument: cstring) ---
	compiler_set_member_name :: proc(compiler: compiler, id: spvc_type_id, member_index: c.uint, argument: cstring) ---
	compiler_unset_decoration :: proc(compiler: compiler, id: SpvId, decoration: SpvDecoration) ---
	compiler_unset_member_decoration :: proc(compiler: compiler, id: spvc_type_id, member_index: c.uint, decoration: SpvDecoration) ---

	compiler_has_decoration :: proc(compiler: compiler, id: SpvId, decoration: SpvDecoration) -> bool ---
	compiler_has_member_decoration :: proc(compiler: compiler, id: spvc_type_id, member_index: c.uint, decoration: SpvDecoration) -> bool ---
	compiler_get_name :: proc(compiler: compiler, id: SpvId) -> cstring ---
	compiler_get_decoration :: proc(compiler: compiler, id: SpvId, decoration: SpvDecoration) -> c.uint ---
	compiler_get_decoration_string :: proc(compiler: compiler, id: SpvId, decoration: SpvDecoration) -> cstring ---
	compiler_get_member_decoration :: proc(compiler: compiler, id: spvc_type_id, member_index: c.uint, decoration: SpvDecoration) -> c.uint ---
	compiler_get_member_decoration_string :: proc(compiler: compiler, id: spvc_type_id, member_index: c.uint, decoration: SpvDecoration) -> cstring ---
	compiler_get_member_name :: proc(compiler: compiler, id: spvc_type_id, member_index: c.uint) -> cstring ---

	/*
 * Entry points.
 * Maps to C++ API.
 */
	compiler_get_entry_points :: proc(compiler: compiler, entry_points: [^]^entry_point, num_entry_points: ^c.size_t) -> result ---
	compiler_set_entry_point :: proc(compiler: compiler, name: cstring, model: SpvExecutionModel) -> result ---
	compiler_rename_entry_point :: proc(compiler: compiler, old_name: cstring, new_name: cstring, model: SpvExecutionModel) -> result ---
	compiler_get_cleansed_entry_point_name :: proc(compiler: compiler, name: cstring, model: SpvExecutionModel) -> cstring ---
	compiler_set_execution_mode :: proc(compiler: compiler, mode: SpvExecutionMode) ---
	compiler_unset_execution_mode :: proc(compiler: compiler, mode: SpvExecutionMode) ---
	compiler_set_execution_mode_with_arguments :: proc(compiler: compiler, mode: SpvExecutionMode, arg0: c.uint, arg1: c.uint, arg2: c.uint) ---
	compiler_get_execution_modes :: proc(compiler: compiler, modes: [^]^SpvExecutionMode, num_modes: ^c.size_t) -> result ---
	compiler_get_execution_mode_argument :: proc(compiler: compiler, mode: SpvExecutionMode) -> c.uint ---
	compiler_get_execution_mode_argument_by_index :: proc(compiler: compiler, mode: SpvExecutionMode, index: c.uint) -> c.uint ---
	compiler_get_execution_model :: proc(compiler: compiler) -> SpvExecutionModel ---
	compiler_update_active_builtins :: proc(compiler: compiler) ---
	compiler_has_active_builtin :: proc(compiler: compiler, builtin: SpvBuiltIn, storage: SpvStorageClass) -> bool ---

	/*
 * Type query interface.
 * Maps to C++ API, except it's read-only.
 */
	compiler_get_type_handle :: proc(compiler: compiler, id: spvc_type_id) -> type ---

	/* Pulls out SPIRType::self. This effectively gives the type ID without array or pointer qualifiers.
 * This is necessary when reflecting decoration/name information on members of a struct,
 * which are placed in the base type, not the qualified type.
 * This is similar to reflected_resource::base_type_id. */
	type_get_base_type_id :: proc(type: type) -> spvc_type_id ---

	type_get_basetype :: proc(type: type) -> basetype ---
	type_get_bit_width :: proc(type: type) -> c.uint ---
	type_get_vector_size :: proc(type: type) -> c.uint ---
	type_get_columns :: proc(type: type) -> c.uint ---
	type_get_num_array_dimensions :: proc(type: type) -> c.uint ---
	type_array_dimension_is_literal :: proc(type: type, dimension: c.uint) -> bool ---
	type_get_array_dimension :: proc(type: type, dimension: c.uint) -> SpvId ---
	type_get_num_member_types :: proc(type: type) -> c.uint ---
	type_get_member_type :: proc(type: type, index: c.uint) -> spvc_type_id ---
	type_get_storage_class :: proc(type: type) -> SpvStorageClass ---

	/* Image type query. */
	type_get_image_sampled_type :: proc(type: type) -> spvc_type_id ---
	type_get_image_dimension :: proc(type: type) -> SpvDim ---
	type_get_image_is_depth :: proc(type: type) -> bool ---
	type_get_image_arrayed :: proc(type: type) -> bool ---
	type_get_image_multisampled :: proc(type: type) -> bool ---
	type_get_image_is_storage :: proc(type: type) -> bool ---
	type_get_image_storage_format :: proc(type: type) -> SpvImageFormat ---
	type_get_image_access_qualifier :: proc(type: type) -> SpvAccessQualifier ---

	/*
 * Buffer layout query.
 * Maps to C++ API.
 */
	compiler_get_declared_struct_size :: proc(compiler: compiler, struct_type: type, size: ^c.size_t) -> result ---
	compiler_get_declared_struct_size_runtime_array :: proc(compiler: compiler, struct_type: type, array_size: c.size_t, size: ^c.size_t) -> result ---
	compiler_get_declared_struct_member_size :: proc(compiler: compiler, type: type, index: c.uint, size: ^c.size_t) -> result ---

	compiler_type_struct_member_offset :: proc(compiler: compiler, type: type, index: c.uint, offset: ^c.uint) -> result ---
	compiler_type_struct_member_array_stride :: proc(compiler: compiler, type: type, index: c.uint, stride: ^c.uint) -> result ---
	compiler_type_struct_member_matrix_stride :: proc(compiler: compiler, type: type, index: c.uint, stride: ^c.uint) -> result ---

	/*
 * Workaround helper functions.
 * Maps to C++ API.
 */
	compiler_build_dummy_sampler_for_combined_images :: proc(compiler: compiler, id: ^variable_id) -> result ---
	compiler_build_combined_image_samplers :: proc(compiler: compiler) -> result ---
	compiler_get_combined_image_samplers :: proc(compiler: compiler, samplers: [^]^combined_image_sampler, num_samplers: ^c.size_t) -> result ---

	/*
 * Constants
 * Maps to C++ API.
 */
	compiler_get_specialization_constants :: proc(compiler: compiler, constants: ^[^]specialization_constant, num_constants: ^c.size_t) -> result ---
	compiler_get_constant_handle :: proc(compiler: compiler, id: constant_id) -> constant ---

	compiler_get_work_group_size_specialization_constants :: proc(compiler: compiler, x: ^specialization_constant, y: ^specialization_constant, z: ^specialization_constant) -> constant_id ---

	/*
 * Buffer ranges
 * Maps to C++ API.
 */
	compiler_get_active_buffer_ranges :: proc(compiler: compiler, id: variable_id, ranges: [^]^buffer_range, num_ranges: ^c.size_t) -> result ---

	/*
 * No stdint.h until C99, sigh :(
 * For smaller types, the result is sign or zero-extended as appropriate.
 * Maps to C++ API.
 * TODO: The SPIRConstant query interface and modification interface is not quite complete.
 */
	constant_get_scalar_fp16 :: proc(constant: constant, column: c.uint, row: c.uint) -> c.float ---
	constant_get_scalar_fp32 :: proc(constant: constant, column: c.uint, row: c.uint) -> c.float ---
	constant_get_scalar_fp64 :: proc(constant: constant, column: c.uint, row: c.uint) -> c.double ---
	constant_get_scalar_u32 :: proc(constant: constant, column: c.uint, row: c.uint) -> c.uint ---
	constant_get_scalar_i32 :: proc(constant: constant, column: c.uint, row: c.uint) -> c.int ---
	constant_get_scalar_u16 :: proc(constant: constant, column: c.uint, row: c.uint) -> c.uint ---
	constant_get_scalar_i16 :: proc(constant: constant, column: c.uint, row: c.uint) -> c.int ---
	constant_get_scalar_u8 :: proc(constant: constant, column: c.uint, row: c.uint) -> c.uint ---
	constant_get_scalar_i8 :: proc(constant: constant, column: c.uint, row: c.uint) -> c.int ---
	constant_get_subconstants :: proc(constant: constant, constituents: [^]^constant_id, count: ^c.size_t) ---
	constant_get_scalar_u64 :: proc(constant: constant, column: c.uint, row: c.uint) -> c.ulonglong ---
	constant_get_scalar_i64 :: proc(constant: constant, column: c.uint, row: c.uint) -> c.longlong ---
	constant_get_type :: proc(constant: constant) -> spvc_type_id ---

	/*
 * C implementation of the C++ api.
 */
	constant_set_scalar_fp16 :: proc(constant: constant, column: c.uint, row: c.uint, value: c.ushort) ---
	constant_set_scalar_fp32 :: proc(constant: constant, column: c.uint, row: c.uint, value: c.float) ---
	constant_set_scalar_fp64 :: proc(constant: constant, column: c.uint, row: c.uint, value: c.double) ---
	constant_set_scalar_u32 :: proc(constant: constant, column: c.uint, row: c.uint, value: c.uint) ---
	constant_set_scalar_i32 :: proc(constant: constant, column: c.uint, row: c.uint, value: c.int) ---
	constant_set_scalar_u64 :: proc(constant: constant, column: c.uint, row: c.uint, value: c.ulonglong) ---
	constant_set_scalar_i64 :: proc(constant: constant, column: c.uint, row: c.uint, value: c.longlong) ---
	constant_set_scalar_u16 :: proc(constant: constant, column: c.uint, row: c.uint, value: c.ushort) ---
	constant_set_scalar_i16 :: proc(constant: constant, column: c.uint, row: c.uint, value: c.short) ---
	constant_set_scalar_u8 :: proc(constant: constant, column: c.uint, row: c.uint, value: c.uchar) ---
	constant_set_scalar_i8 :: proc(constant: constant, column: c.uint, row: c.uint, value: c.char) ---

	/*
 * Misc reflection
 * Maps to C++ API.
 */
	compiler_get_binary_offset_for_decoration :: proc(compiler: compiler, id: variable_id, decoration: SpvDecoration, word_offset: c.uint) -> bool ---

	compiler_buffer_is_hlsl_counter_buffer :: proc(compiler: compiler, id: variable_id) -> bool ---
	compiler_buffer_get_hlsl_counter_buffer :: proc(compiler: compiler, id: variable_id, counter_id: ^variable_id) -> bool ---

	compiler_get_declared_capabilities :: proc(compiler: compiler, capabilities: ^[^]SpvCapability, num_capabilities: ^c.size_t) -> result ---
	compiler_get_declared_extensions :: proc(compiler: compiler, extensions: ^cstring, num_extensions: ^c.size_t) -> result ---

	compiler_get_remapped_declared_block_name :: proc(compiler: compiler, id: variable_id) -> cstring ---
	compiler_get_buffer_block_decorations :: proc(compiler: compiler, id: variable_id, decorations: [^]^SpvDecoration, num_decorations: ^c.size_t) -> result ---
}
