package raytracer

import "core:fmt"
import "core:log"
import glm "core:math/linalg"
import "vendor:glfw"
import vk "vendor:vulkan"
_ :: fmt
_ :: glm

Global_Ubo :: struct {
	projection:         Mat4,
	view:               Mat4,
	inverse_view:       Mat4,
	inverse_projection: Mat4,
}

Render_Error :: union {
	Pipeline_Error,
	Shader_Error,
	Swapchain_Error,
}

Renderer :: struct {
	ctx:                    Vulkan_Context,
	window:                 ^Window,
	scene:                  Scene,
	camera:                 Camera,
	input_system:           Input_System,
	// TODO: probably move this in the future
	shaders:                [dynamic]Shader,

	// ray tracing properties
	rt_properties:          vk.PhysicalDeviceRayTracingPipelinePropertiesKHR,
	descriptor_set_manager: Descriptor_Set_Manager,
	ui_ctx:                 UI_Context,
	rt_ctx:                 Raytracing_Context,

	// time
	last_frame_time:        f64,
	delta_time:             f32,
	accumulation_frame:     u32,
}

renderer_init :: proc(renderer: ^Renderer, window: ^Window, allocator := context.allocator) {
	renderer.window = window
	vulkan_context_init(&renderer.ctx, window, allocator)

	descriptor_set_manager2_init(&renderer.descriptor_set_manager, renderer.ctx.device)
	renderer.rt_properties.sType = .PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_PROPERTIES_KHR
	props := vk.PhysicalDeviceProperties2 {
		sType = .PHYSICAL_DEVICE_PROPERTIES_2,
		pNext = &renderer.rt_properties,
	}
	vk.GetPhysicalDeviceProperties2(renderer.ctx.device.physical_device.ptr, &props)

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

	renderer.scene = create_scene(renderer.ctx.device)
	scene_create_as(&renderer.scene, renderer.ctx.device)
	scene_create_buffers(&renderer.scene, renderer.ctx.device)
	{
		shader: [3]Shader
		shader_init(
			&shader[0],
			renderer.ctx.device,
			"main",
			"main",
			"shaders/rgen.spv",
			{.RAYGEN_KHR},
		)
		shader_init(
			&shader[1],
			renderer.ctx.device,
			"main",
			"main",
			"shaders/rmiss.spv",
			{.MISS_KHR},
		)
		shader_init(
			&shader[2],
			renderer.ctx.device,
			"main",
			"main",
			"shaders/rchit.spv",
			{.CLOSEST_HIT_KHR},
		)

		// rt_init(
		// 	&renderer.rt_ctx,
		// 	&renderer.ctx,
		// 	renderer.descriptor_set_manager,
		// 	push_constants = {
		// 		{stageFlags = {.RAYGEN_KHR}, offset = 0, size = size_of(Raytracing_Push_Constant)},
		// 	},
		// 	shaders = shader[:],
		// )
	}

	camera_init(
		&renderer.camera,
		{0, 0, -3},
		window_aspect_ratio(window^),
		renderer.ctx.device,
		renderer.descriptor_set_manager.pool,
	)
}

renderer_destroy :: proc(renderer: ^Renderer) {
	vk.DeviceWaitIdle(renderer.ctx.device.logical_device.ptr)

	scene_destroy(&renderer.scene, renderer.ctx.device)
	input_system_destroy(&renderer.input_system)
	for &shader in renderer.shaders {
		shader_destroy(&shader)
	}
	delete(renderer.shaders)
	ui_context_destroy(&renderer.ui_ctx, renderer.ctx.device)
	window_destroy(renderer.window^)
	ctx_destroy(&renderer.ctx)
}

// FIXME: in the future change this
renderer_handle_mouse :: proc(renderer: ^Renderer, x, y: f32) {
	move_camera := input_system_is_mouse_key_pressed(renderer.input_system, .MOUSE_BUTTON_2)
	if move_camera {
		renderer.accumulation_frame = 0
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

	moved: bool
	if input_system_is_key_pressed(renderer.input_system, .W) {
		moved = true
		camera_move(&renderer.camera, .Front, renderer.delta_time)
	}
	if input_system_is_key_pressed(renderer.input_system, .S) {
		moved = true
		camera_move(&renderer.camera, .Backwards, renderer.delta_time)
	}
	if input_system_is_key_pressed(renderer.input_system, .D) {
		moved = true
		camera_move(&renderer.camera, .Right, renderer.delta_time)
	}
	if input_system_is_key_pressed(renderer.input_system, .A) {
		moved = true
		camera_move(&renderer.camera, .Left, renderer.delta_time)
	}
	if input_system_is_key_pressed(renderer.input_system, .Space) {
		moved = true
		camera_move(&renderer.camera, .Up, renderer.delta_time)
	}
	if input_system_is_key_pressed(renderer.input_system, .Left_Shift) {
		moved = true
		camera_move(&renderer.camera, .Down, renderer.delta_time)
	}

	if input_system_is_key_pressed(renderer.input_system, .Q) {
		window_set_should_close(renderer.window^)
	}

	if moved {
		renderer.accumulation_frame = 0
	}
}

renderer_render :: proc(renderer: ^Renderer) {
	if renderer.window.framebuffer_resized {
		renderer.window.framebuffer_resized = false
		renderer_handle_resizing(renderer)
	}

	camera_update_buffers(&renderer.camera, renderer.ctx.current_frame)

	image_index, err := ctx_begin_frame(&renderer.ctx)

	cmd := ctx_request_command_buffer(&renderer.ctx)

	if err != nil do return

	ui_render(renderer.ctx, &Command_Buffer{buffer = cmd}, renderer)

	_ = vk_check(vk.EndCommandBuffer(cmd), "Failed to end command buffer")
	ctx_swapchain_present(&renderer.ctx, cmd, image_index)

	renderer.accumulation_frame += 1
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
