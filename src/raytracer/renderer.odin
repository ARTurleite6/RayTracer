package raytracer

import "core:fmt"
import "core:log"
import glm "core:math/linalg"
import "vendor:glfw"
import vk "vendor:vulkan"
_ :: fmt
_ :: glm

Global_Ubo :: struct {
	projection:   Mat4,
	view:         Mat4,
	inverse_view: Mat4,
}

Render_Error :: union {
	Pipeline_Error,
	Shader_Error,
	Swapchain_Error,
}

Renderer :: struct {
	ctx:             Vulkan_Context,
	window:          ^Window,
	scene:           Scene,
	camera:          Camera,
	render_graph:    Render_Graph,
	input_system:    Input_System,
	// TODO: probably move this in the future
	shaders:         [dynamic]Shader,
	ui_ctx:          UI_Context,

	// time
	last_frame_time: f64,
	delta_time:      f32,
}

renderer_init :: proc(renderer: ^Renderer, window: ^Window, allocator := context.allocator) {
	renderer.window = window
	vulkan_context_init(&renderer.ctx, window, allocator)

	window_set_window_user_pointer(window, renderer.window)
	input_system_init(&renderer.input_system, allocator)
	event_handler := Event_Handler {
		data     = renderer,
		on_event = renderer_on_event,
	}
	window_set_event_handler(window, event_handler)

	ui_context_init(
		&renderer.ui_ctx,
		renderer.ctx.device,
		renderer.window^,
		renderer.ctx.swapchain_manager.format,
	)

	{ 	// create shaders
		shader: Shader
		shader_init(&shader, renderer.ctx.device, "main", "main", "shaders/vert.spv", {.VERTEX})
		append(&renderer.shaders, shader)

		shader_init(&shader, renderer.ctx.device, "main", "main", "shaders/frag.spv", {.FRAGMENT})
		append(&renderer.shaders, shader)
	}

	renderer.scene = create_scene(renderer.ctx.device)

	render_graph_init(
		&renderer.render_graph,
		renderer.ctx.device,
		&renderer.ctx.swapchain_manager,
		allocator,
	)
	{ 	// create graphics stage
		stage := new(Graphics_Stage)
		graphics_stage_init(stage, "main", allocator)
		graphics_stage_use_shader(stage, renderer.shaders[0])
		graphics_stage_use_shader(stage, renderer.shaders[1])
		graphics_stage_use_format(stage, renderer.ctx.swapchain_manager.format)
		graphics_stage_use_vertex_buffer_binding(
			stage,
			0,
			VERTEX_INPUT_ATTRIBUTE_DESCRIPTION[:],
			VERTEX_INPUT_BINDING_DESCRIPTION,
		)
		render_stage_use_push_constant_range(
			stage,
			vk.PushConstantRange {
				stageFlags = {.VERTEX},
				offset = 0,
				size = size_of(Push_Constants),
			},
		)
		render_stage_use_descriptor_layout(stage, renderer.ctx.descriptor_layout.handle)
		render_stage_add_color_attachment(
			stage,
			load_op = .CLEAR,
			store_op = .STORE,
			clear_value = vk.ClearValue {
				color = vk.ClearColorValue{float32 = {0.01, 0.01, 0.01, 1.0}},
			},
		)
		render_graph_add_stage(&renderer.render_graph, stage)
	}

	{
		stage := new(UI_Stage)
		ui_stage_init(stage, "ui", allocator)
		render_stage_add_color_attachment(
			stage,
			.LOAD,
			.STORE,
			vk.ClearValue{color = vk.ClearColorValue{float32 = {0.01, 0.01, 0.01, 1.0}}},
		)

		render_graph_add_stage(&renderer.render_graph, stage)
	}

	render_graph_compile(&renderer.render_graph)

	camera_init(&renderer.camera, position = {0, 0, -3}, aspect = window_aspect_ratio(window^))
}

renderer_destroy :: proc(renderer: ^Renderer) {
	vk.DeviceWaitIdle(renderer.ctx.device.logical_device.ptr)

	render_graph_destroy(&renderer.render_graph)
	scene_destroy(&renderer.scene, renderer.ctx.device)
	for &shader in renderer.shaders {
		shader_destroy(&shader)
	}
	delete(renderer.shaders)
	ui_context_destroy(&renderer.ui_ctx, renderer.ctx.device)
	window_destroy(renderer.window^, renderer.ctx.device.instance.ptr)
	ctx_destroy(&renderer.ctx)
}

// FIXME: in the future change this
renderer_handle_mouse :: proc(renderer: ^Renderer, x, y: f32) {
	move_camera := input_system_is_mouse_key_pressed(renderer.input_system, .MOUSE_BUTTON_2)
	if move_camera {
		window_set_input_mode(renderer.window^, .Locked)
	} else {
		window_set_input_mode(renderer.window^, .Normal)
	}
	camera_process_mouse(&renderer.camera, x, y, move = move_camera)
}

renderer_run :: proc(renderer: ^Renderer) {
	for !window_should_close(renderer.window^) {
		free_all(context.temp_allocator)
		renderer_update(renderer)
		renderer_render(renderer)
	}
}

renderer_update :: proc(renderer: ^Renderer) {
	current_time := glfw.GetTime()
	renderer.delta_time = f32(current_time - renderer.last_frame_time)
	renderer.last_frame_time = current_time

	glfw.PollEvents()
	window_update(renderer.window^)

	if input_system_is_key_pressed(renderer.input_system, .W) {
		camera_move(&renderer.camera, .Front, renderer.delta_time)
	}
	if input_system_is_key_pressed(renderer.input_system, .S) {
		camera_move(&renderer.camera, .Backwards, renderer.delta_time)
	}
	if input_system_is_key_pressed(renderer.input_system, .D) {
		camera_move(&renderer.camera, .Right, renderer.delta_time)
	}
	if input_system_is_key_pressed(renderer.input_system, .A) {
		camera_move(&renderer.camera, .Left, renderer.delta_time)
	}
	if input_system_is_key_pressed(renderer.input_system, .Space) {
		camera_move(&renderer.camera, .Up, renderer.delta_time)
	}
	if input_system_is_key_pressed(renderer.input_system, .Left_Shift) {
		camera_move(&renderer.camera, .Down, renderer.delta_time)
	}

	if input_system_is_key_pressed(renderer.input_system, .Q) {
		window_set_should_close(renderer.window^)
	}
}

renderer_render :: proc(renderer: ^Renderer) {
	if renderer.window.framebuffer_resized {
		renderer.window.framebuffer_resized = false
		renderer_handle_resizing(renderer)
	}

	cmd, image_index, err := ctx_begin_frame(&renderer.ctx)

	if err != nil do return

	ubo := &Global_Ubo {
		view = renderer.camera.view,
		projection = renderer.camera.proj,
		inverse_view = renderer.camera.inverse_view,
	}
	ctx_update_uniform_buffer(&renderer.ctx, ubo)


	_ = vk_check(
		vk.BeginCommandBuffer(cmd, &vk.CommandBufferBeginInfo{sType = .COMMAND_BUFFER_BEGIN_INFO}),
		"Failed to begin command buffer",
	)

	render_graph_render(
		&renderer.render_graph,
		cmd,
		image_index,
		{renderer = renderer, descriptor_set = ctx_get_descriptor_set(renderer.ctx)},
	)

	_ = vk_check(vk.EndCommandBuffer(cmd), "Failed to end command buffer")
	ctx_swapchain_present(&renderer.ctx, cmd, image_index)
}

@(private = "file")
renderer_handle_resizing :: proc(
	renderer: ^Renderer,
	allocator := context.allocator,
) -> Swapchain_Error {
	extent := window_get_extent(renderer.window^)
	camera_update_aspect_ratio(&renderer.camera, window_aspect_ratio(renderer.window^))
	return ctx_handle_resize(&renderer.ctx, extent.width, extent.height, allocator)
}

@(private = "file")
renderer_on_event :: proc(handler: ^Event_Handler, event: Event) {
	renderer := cast(^Renderer)handler.data

	switch v in event {
	case Mouse_Button_Event:
		input_system_register_mouse_button(&renderer.input_system, v.key, v.action)
	case Key_Event:
		input_system_register_key(&renderer.input_system, v.key, v.action)
	case Resize_Event:
		window_resize(renderer.window, v.width, v.height)
	case Mouse_Event:
		renderer_handle_mouse(renderer, v.x, v.y)
	}
}

@(private)
@(require_results)
vk_check :: proc(result: vk.Result, message: string) -> vk.Result {
	if result != .SUCCESS {
		log.errorf(fmt.tprintf("%s: \x1b[31m%v\x1b[0m", message, result))
		return result
	}
	return nil
}
