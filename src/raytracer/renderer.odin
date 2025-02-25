package raytracer

import "core:fmt"
import "core:log"
import glm "core:math/linalg"
import "vendor:glfw"
import vk "vendor:vulkan"
_ :: fmt
_ :: glm


// TODO: change this
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
	device:                   ^Device,
	swapchain_manager:        Swapchain_Manager,
	pipeline_manager:         Pipeline_Manager,
	window:                   ^Window,
	scene:                    Scene,
	camera:                   Camera,
	render_graph:             Render_Graph,
	// TODO: probably move this in the future
	shaders:                  [dynamic]Shader,
	pool:                     vk.DescriptorPool,
	ubos:                     [MAX_FRAMES_IN_FLIGHT]Buffer,
	global_descriptor_layout: Descriptor_Set_Layout,
	descriptor_sets:          [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
}

renderer_init :: proc(renderer: ^Renderer, window: ^Window, allocator := context.allocator) {
	// context_init(&renderer.ctx, window, allocator) or_return
	renderer.window = window
	renderer.device = new(Device)
	if err := device_init(renderer.device, renderer.window); err != .None {
		fmt.println("Error on device: %v", err)
		return
	}

	surface, _ := window_get_surface(renderer.window, renderer.device.instance)
	swapchain_manager_init(
		&renderer.swapchain_manager,
		renderer.device,
		surface,
		{extent = window_get_extent(window^), vsync = true},
	)

	pipeline_manager_init(&renderer.pipeline_manager, renderer.device)

	{ 	// pool
		builder := &Descriptor_Pool_Builder{}
		descriptor_pool_builder_init(builder, renderer.device)
		descriptor_pool_builder_set_max_sets(builder, MAX_FRAMES_IN_FLIGHT)
		descriptor_pool_builder_add_pool_size(builder, .UNIFORM_BUFFER, MAX_FRAMES_IN_FLIGHT)
		renderer.pool, _ = descriptor_pool_build(builder)
		descriptor_pool_builder_init(builder, renderer.device)
	}

	for &buffer in renderer.ubos {
		buffer_init(
			&buffer,
			renderer.device,
			size_of(Global_Ubo),
			1,
			{.UNIFORM_BUFFER},
			.Cpu_To_Gpu,
		)

		buffer_map(&buffer, renderer.device)
	}

	{
		builder := &Descriptor_Set_Layout_Builder{}
		descriptor_layout_builder_init(builder, renderer.device)
		descriptor_layout_builder_add_binding(builder, 0, .UNIFORM_BUFFER, {.VERTEX})
		renderer.global_descriptor_layout, _ = descriptor_layout_build(builder)
	}

	{ 	// descriptor sets
		writer := &Descriptor_Writer{}
		descriptor_writer_init(
			writer,
			renderer.global_descriptor_layout,
			renderer.pool,
			renderer.device,
		)

		for buffer, i in renderer.ubos {
			buffer_info := vk.DescriptorBufferInfo {
				buffer = buffer.handle,
				offset = 0,
				range  = vk.DeviceSize(size_of(Global_Ubo)),
			}
			descriptor_writer_write_buffer(writer, 0, &buffer_info)

			renderer.descriptor_sets[i], _ = descriptor_writer_build(writer)
		}
	}

	{ 	// create shaders
		shader: Shader
		shader_init(&shader, renderer.device, "main", "main", "shaders/vert.spv", {.VERTEX})
		append(&renderer.shaders, shader)

		shader_init(&shader, renderer.device, "main", "main", "shaders/frag.spv", {.FRAGMENT})
		append(&renderer.shaders, shader)
	}

	renderer.scene = create_scene(renderer.device)

	render_graph_init(
		&renderer.render_graph,
		renderer.device,
		&renderer.swapchain_manager,
		allocator,
	)
	{ 	// create graphics stage
		stage := new(Graphics_Stage)
		graphics_stage_init(stage, "main", allocator)
		graphics_stage_use_shader(stage, renderer.shaders[0])
		graphics_stage_use_shader(stage, renderer.shaders[1])
		graphics_stage_use_format(stage, renderer.swapchain_manager.format)
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
		render_stage_use_descriptor_layout(stage, renderer.global_descriptor_layout.handle)

		render_graph_add_stage(&renderer.render_graph, stage)
	}

	render_graph_compile(&renderer.render_graph)

	// // mesh_init_without_indices(&renderer.mesh, &renderer.ctx, "Triangle", VERTICES) or_return
	// renderer.mesh = create_quad(&renderer.ctx, "Triangle") or_return

	camera_init(&renderer.camera, aspect = window_aspect_ratio(window^))
}

renderer_destroy :: proc(renderer: ^Renderer) {
	vk.DeviceWaitIdle(renderer.device.logical_device.ptr)
	render_graph_destroy(&renderer.render_graph)
	scene_destroy(&renderer.scene, renderer.device)

	for &shader in renderer.shaders {
		shader_destroy(&shader)
	}

	for &ubo in renderer.ubos {
		buffer_destroy(&ubo, renderer.device)
	}

	vk.DestroyDescriptorPool(renderer.device.logical_device.ptr, renderer.pool, nil)
	vk.DestroyDescriptorSetLayout(
		renderer.device.logical_device.ptr,
		renderer.global_descriptor_layout.handle,
		nil,
	)

	pipeline_manager_destroy(&renderer.pipeline_manager)
	swapchain_manager_destroy(&renderer.swapchain_manager)
	device_destroy(renderer.device)
}

renderer_run :: proc(renderer: ^Renderer) {
	for !window_should_close(renderer.window^) {
		renderer_update(renderer)
		renderer_render(renderer)
	}
}

renderer_update :: proc(renderer: ^Renderer) {
	glfw.PollEvents()
	window_update(renderer.window^)
}

renderer_render :: proc(renderer: ^Renderer) {
	if renderer.window.framebuffer_resized {
		renderer.window.framebuffer_resized = false
		renderer_handle_resizing(renderer)
	}

	cmd, image_index, err := begin_frame(renderer)
	if err != nil {
		return
	}

	// FIXME: this should be on update, both this and the begin_frame
	ubo := &Global_Ubo {
		view = renderer.camera.view,
		projection = renderer.camera.proj,
		inverse_view = glm.matrix4_inverse(renderer.camera.view),
	}
	buffer_write(&renderer.ubos[renderer.swapchain_manager.frame_manager.current_frame], ubo)
	buffer_flush(
		&renderer.ubos[renderer.swapchain_manager.frame_manager.current_frame],
		renderer.device^,
	)


	_ = vk_check(
		vk.BeginCommandBuffer(cmd, &vk.CommandBufferBeginInfo{sType = .COMMAND_BUFFER_BEGIN_INFO}),
		"Failed to begin command buffer",
	)

	render_graph_render(
		&renderer.render_graph,
		cmd,
		image_index,
		{
			scene = &renderer.scene,
			descriptor_set = renderer.descriptor_sets[renderer.swapchain_manager.frame_manager.current_frame],
		},
	)

	_ = vk_check(vk.EndCommandBuffer(cmd), "Failed to end command buffer")
	swapchain_present(&renderer.swapchain_manager, {cmd}, image_index)
}

@(private = "file")
begin_frame :: proc(
	renderer: ^Renderer,
) -> (
	cmd: vk.CommandBuffer,
	image_index: u32,
	err: Render_Error,
) {
	frame := frame_manager_get_frame(&renderer.swapchain_manager.frame_manager)

	frame_wait(frame, renderer.device)

	result := swapchain_acquire_next_image(
		&renderer.swapchain_manager,
		frame.sync.image_available,
	) or_return

	_ = vk_check(
		vk.ResetFences(renderer.device.logical_device.ptr, 1, &frame.sync.in_flight_fence),
		"Error reseting in_flight_fence",
	)

	cmd = frame.commands.primary_buffer
	_ = vk_check(vk.ResetCommandBuffer(cmd, {}), "Error reseting command buffer")


	return cmd, result.image_index, nil
}

@(private = "file")
renderer_handle_resizing :: proc(
	renderer: ^Renderer,
	allocator := context.allocator,
) -> Swapchain_Error {
	extent := window_get_extent(renderer.window^)
	return swapchain_recreate(&renderer.swapchain_manager, extent.width, extent.height, allocator)
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
