package raytracer

import "core:fmt"
import glm "core:math/linalg"
import vk "vendor:vulkan"
_ :: fmt
_ :: glm

Render_Error :: union {
	Swapchain_Error,
}

Renderer :: struct {
	device:            ^Device,
	swapchain_manager: Swapchain_Manager,
	pipeline_manager:  Pipeline_Manager,
	frame_manager:     Frame_Manager,
	pending_resize:    bool,
	ctx:               Context,
	window:            ^Window,
	mesh:              Mesh,
	camera:            Camera,
}

VERTICES := []Vertex {
	{{0.0, -0.5, 0.0}, {1.0, 0.0, 0.0}},
	{{0.5, 0.5, 0.0}, {0.0, 1.0, 0.0}},
	{{-0.5, 0.5, 0.0}, {0.0, 0.0, 1.0}},
}

renderer_init :: proc(
	renderer: ^Renderer,
	window: ^Window,
	allocator := context.allocator,
) -> (
	err: Backend_Error,
) {
	// context_init(&renderer.ctx, window, allocator) or_return
	renderer.window = window
	renderer.device = new(Device)
	if err := device_init(renderer.device, renderer.window); err != .None {
		fmt.println("Error on device: %v", err)
		return
	}

	swapchain_manager_init(
		&renderer.swapchain_manager,
		renderer.device,
		window_get_surface(renderer.window, renderer.device.instance) or_return,
		{extent = window_get_extent(window^), vsync = true},
	)

	pipeline_manager_init(&renderer.pipeline_manager, renderer.device)

	_ = create_graphics_pipeline2(
		&renderer.pipeline_manager,
		"main",
		{
			color_attachment = renderer.swapchain_manager.format,
			shader_stages = []Shader_Stage_Info {
				{stage = {.VERTEX}, entry = "main", file_path = "shaders/vert.spv"},
				{stage = {.FRAGMENT}, entry = "main", file_path = "shaders/frag.spv"},
			},
		},
	)

	_ = frame_manager_init(&renderer.frame_manager, renderer.device)

	// // mesh_init_without_indices(&renderer.mesh, &renderer.ctx, "Triangle", VERTICES) or_return
	// renderer.mesh = create_quad(&renderer.ctx, "Triangle") or_return

	camera_init(&renderer.camera, aspect = window_aspect_ratio(window^))
	return nil
}

renderer_destroy :: proc(renderer: ^Renderer) {
	vk.DeviceWaitIdle(renderer.device.logical_device.ptr)
	// mesh_destroy(&renderer.mesh)

	frame_manager_destroy(&renderer.frame_manager)
	pipeline_manager_destroy(&renderer.pipeline_manager)
	swapchain_manager_destroy(&renderer.swapchain_manager)
	device_destroy(renderer.device)
	// delete_context(&renderer.ctx)
}

renderer_begin_frame :: proc(renderer: ^Renderer) -> Render_Error {
	if renderer.pending_resize {
		// TODO: handle resize
		renderer.pending_resize = false
	}

	frame := frame_manager_get_frame(&renderer.frame_manager)
	frame_wait(frame, renderer.device)

	result, acquire_err := swapchain_acquire_next_image(
		&renderer.swapchain_manager,
		frame.sync.image_available,
	)
	if acquire_err != .None {
		if acquire_err == .Out_Of_Date {
			renderer.pending_resize = true
		}
		return acquire_err
	}

	if result.suboptimal {
		renderer.pending_resize = true
	}

	return nil
}
