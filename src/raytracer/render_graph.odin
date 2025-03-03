package raytracer

import "core:fmt"
import "core:slice"
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
	reads:              [dynamic]Render_Resource,
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

Render_Resource :: union {
	Buffer,
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
	stages:    [dynamic]^Render_Stage,
	swapchain: ^Swapchain_Manager,
	device:    ^Device,
}

render_graph_init :: proc(
	graph: ^Render_Graph,
	device: ^Device,
	swapchain: ^Swapchain_Manager,
	allocator := context.allocator,
) {
	graph.stages = make([dynamic]^Render_Stage, allocator)
	graph.swapchain = swapchain
	graph.device = device
}

render_graph_destroy :: proc(graph: ^Render_Graph) {
	for stage in graph.stages {
		render_stage_destroy(stage, graph.device^)
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
			build_graphics_pipeline(v, graph.device^)
		case ^UI_Stage:
		// for now we dont have nothing in here
		case ^Raytracing_Stage:
			build_raytracing_pipeline(v, graph.device^)
		}
	}
}

render_graph_render :: proc(
	graph: ^Render_Graph,
	cmd: vk.CommandBuffer,
	image_index: u32,
	render_data: Render_Data,
) {
	image_transition(
		cmd,
		{
			image = graph.swapchain.images[image_index],
			old_layout = .UNDEFINED,
			new_layout = .COLOR_ATTACHMENT_OPTIMAL,
			src_stage = {.TOP_OF_PIPE},
			dst_stage = {.COLOR_ATTACHMENT_OUTPUT},
			src_access = {},
			dst_access = {.COLOR_ATTACHMENT_WRITE},
		},
	)

	for stage in graph.stages {
		record_command_buffer(graph^, stage^, cmd, image_index, render_data)
	}
	image_transition(
		cmd,
		{
			image = graph.swapchain.images[image_index],
			old_layout = .COLOR_ATTACHMENT_OPTIMAL,
			new_layout = .PRESENT_SRC_KHR,
			src_stage = {.COLOR_ATTACHMENT_OUTPUT},
			dst_stage = {.BOTTOM_OF_PIPE},
			src_access = {.COLOR_ATTACHMENT_WRITE},
			dst_access = {},
		},
	)
}

render_stage_init :: proc(
	stage: ^Render_Stage,
	name: string,
	variant: Render_Stage_Variant,
	allocator := context.allocator,
) {
	stage.name = name
	stage.reads = make([dynamic]Render_Resource, allocator)
	stage.descriptor_layouts = make([dynamic]vk.DescriptorSetLayout, allocator)
	stage.push_constants = make([dynamic]vk.PushConstantRange, allocator)
	stage.color_attachments = make([dynamic]Color_Attachment, allocator)
	stage.variant = variant
}

render_stage_destroy :: proc(stage: ^Render_Stage, device: Device) {
	switch v in stage.variant {
	case ^Graphics_Stage:
		graphics_stage_destroy(v, device)
		free(v)
	case ^UI_Stage:
		free(v)
	case ^Raytracing_Stage:
	}
	delete(stage.reads)
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
	begin_render_pass(graph, stage, cmd, image_index)
	#partial switch v in stage.variant {
	case ^Graphics_Stage:
		graphics_stage_render(graph, v, cmd, image_index, render_data)
	case ^UI_Stage:
		ui_stage_render(graph, v, cmd, image_index, render_data)
	case ^Raytracing_Stage:
		raytracing_render(graph, v, cmd, image_index, render_data)
	}
	end_render_pass(graph, cmd, image_index)
}

@(private = "file")
begin_render_pass :: proc(
	render_graph: Render_Graph,
	stage: Render_Stage,
	cmd: vk.CommandBuffer,
	image_index: u32,
) {
	image_view := render_graph.swapchain.image_views[image_index]

	context.user_ptr = &image_view
	color_attachments := slice.mapper(
		stage.color_attachments[:],
		proc(ca: Color_Attachment) -> vk.RenderingAttachmentInfo {
			return color_attachment_to_rendering_info(ca, (cast(^vk.ImageView)context.user_ptr)^)
		},
		context.temp_allocator,
	)

	extent := render_graph.swapchain.extent
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = extent},
		layerCount = 1,
		colorAttachmentCount = u32(len(color_attachments)),
		pColorAttachments = raw_data(color_attachments),
	}

	vk.CmdBeginRendering(cmd, &rendering_info)

	viewport := vk.Viewport {
		minDepth = 0,
		maxDepth = 1,
		width    = f32(extent.width),
		height   = f32(extent.height),
	}

	scissor := vk.Rect2D {
		extent = extent,
	}

	vk.CmdSetViewport(cmd, 0, 1, &viewport)
	vk.CmdSetScissor(cmd, 0, 1, &scissor)
}

@(private = "file")
end_render_pass :: proc(graph: Render_Graph, cmd: vk.CommandBuffer, image_index: u32) {
	vk.CmdEndRendering(cmd)
}

@(private = "file")
@(require_results)
color_attachment_to_rendering_info :: proc(
	attachment: Color_Attachment,
	image_view: vk.ImageView,
) -> vk.RenderingAttachmentInfo {
	return vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = image_view,
		imageLayout = attachment.image_layout,
		loadOp = attachment.load_op,
		storeOp = attachment.store_op,
		clearValue = attachment.clear_value,
	}
}
