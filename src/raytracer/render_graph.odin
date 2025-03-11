package raytracer

import "core:fmt"
import vk "vendor:vulkan"
_ :: fmt

Pipeline :: struct {
	handle: vk.Pipeline,
	layout: vk.PipelineLayout,
}

Color_Attachment :: struct {
	load_op:      vk.AttachmentLoadOp,
	store_op:     vk.AttachmentStoreOp,
	clear_value:  vk.ClearValue,
	image_layout: vk.ImageLayout,
}

Render_Stage :: struct {
	name:               string,
	descriptor_layouts: [dynamic]vk.DescriptorSetLayout,
	push_constants:     [dynamic]vk.PushConstantRange,
	color_attachments:  [dynamic]Color_Attachment,
	variant:            Render_Stage_Variant,
}

// TODO: see if this is needed
Render_Data :: struct {
	renderer:           ^Renderer,
	descriptor_manager: ^Descriptor_Set_Manager,
	frame_index:        u32,
}

Render_Stage_Variant :: union {
	^Graphics_Stage,
	^UI_Stage,
	^Raytracing_Stage,
}

Vertex_Buffer_Binding :: struct {
	value:                 u32,
	binding_description:   vk.VertexInputBindingDescription,
	attribute_description: []vk.VertexInputAttributeDescription,
}

Pipeline_Error :: enum {
	None = 0,
	Cache_Creation_Failed,
	Layout_Creation_Failed,
	Pipeline_Creation_Failed,
	Descriptor_Set_Creation_Failed,
	Pool_Creation_Failed,
	Shader_Creation_Failed,
}


Render_Graph :: struct {
	stages: [dynamic]^Render_Stage,
	ctx:    ^Vulkan_Context,
}

render_graph_init :: proc(
	graph: ^Render_Graph,
	ctx: ^Vulkan_Context,
	swapchain: ^Swapchain_Manager,
	allocator := context.allocator,
) {
	graph.stages = make([dynamic]^Render_Stage, allocator)
	graph.ctx = ctx
}

render_graph_destroy :: proc(graph: ^Render_Graph) {
	for stage in graph.stages {
		render_stage_destroy(stage, graph.ctx.device)
	}
	delete(graph.stages)
	graph.stages = nil
}

render_graph_add_stage :: proc(graph: ^Render_Graph, stage: ^Render_Stage) {
	append(&graph.stages, stage)
}

render_graph_compile :: proc(graph: ^Render_Graph) {
	for stage in graph.stages {
		switch v in stage.variant {
		case ^Graphics_Stage:
			build_graphics_pipeline(v, graph.ctx.device^)
		case ^UI_Stage:
		case ^Raytracing_Stage:
			create_rt_pipeline(v, graph.ctx.device)
		// for now we dont have nothing in here
		}
	}
}

render_graph_render :: proc(
	graph: ^Render_Graph,
	cmd: vk.CommandBuffer,
	image_index: u32,
	render_data: Render_Data,
) {
	for stage in graph.stages {
		record_command_buffer(graph^, stage^, cmd, image_index, render_data)
	}
}

render_stage_init :: proc(
	stage: ^Render_Stage,
	name: string,
	variant: Render_Stage_Variant,
	allocator := context.allocator,
) {
	stage.name = name
	stage.descriptor_layouts = make([dynamic]vk.DescriptorSetLayout, allocator)
	stage.push_constants = make([dynamic]vk.PushConstantRange, allocator)
	stage.color_attachments = make([dynamic]Color_Attachment, allocator)
	stage.variant = variant
}

render_stage_destroy :: proc(stage: ^Render_Stage, device: ^Device) {
	switch v in stage.variant {
	case ^Graphics_Stage:
		// graphics_stage_destroy(v, device^)
		free(v)
	case ^UI_Stage:
		free(v)
	case ^Raytracing_Stage:
		// 	raytracing_destroy(v, device)
		free(v)
	}
	delete(stage.descriptor_layouts)
	delete(stage.push_constants)
	delete(stage.color_attachments)

	stage^ = {}
}

render_stage_use_descriptor_layout :: proc(stage: ^Render_Stage, layout: vk.DescriptorSetLayout) {
	append(&stage.descriptor_layouts, layout)
}

render_stage_use_push_constant_range :: proc(stage: ^Render_Stage, range: vk.PushConstantRange) {
	append(&stage.push_constants, range)
}

render_stage_add_color_attachment :: proc(
	stage: ^Render_Stage,
	load_op: vk.AttachmentLoadOp,
	store_op: vk.AttachmentStoreOp,
	clear_value: vk.ClearValue,
	image_layout: vk.ImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
) {
	append_elem(
		&stage.color_attachments,
		Color_Attachment {
			load_op = load_op,
			store_op = store_op,
			clear_value = clear_value,
			image_layout = image_layout,
		},
	)
}

@(private = "file")
record_command_buffer :: proc(
	graph: Render_Graph,
	stage: Render_Stage,
	cmd: vk.CommandBuffer,
	image_index: u32,
	render_data: Render_Data,
) {
	switch v in stage.variant {
	case ^Graphics_Stage:
		graphics_stage_render(graph, v, cmd, image_index, render_data)
	case ^UI_Stage:
		ui_stage_render(graph, v, cmd, image_index, render_data)
	case ^Raytracing_Stage:
		raytracing_render(graph, v, cmd, image_index, render_data)
	}
}
