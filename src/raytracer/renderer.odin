package raytracer

import "core:fmt"
import "core:log"
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
	window:            ^Window,
	scene:             Scene,
	camera:            Camera,
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

	_ = create_graphics_pipeline(
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

	renderer.scene = create_scene(renderer.device)
	// // mesh_init_without_indices(&renderer.mesh, &renderer.ctx, "Triangle", VERTICES) or_return
	// renderer.mesh = create_quad(&renderer.ctx, "Triangle") or_return

	camera_init(&renderer.camera, aspect = window_aspect_ratio(window^))
}

renderer_destroy :: proc(renderer: ^Renderer) {
	vk.DeviceWaitIdle(renderer.device.logical_device.ptr)
	scene_destroy(&renderer.scene, renderer.device)

	pipeline_manager_destroy(&renderer.pipeline_manager)
	swapchain_manager_destroy(&renderer.swapchain_manager)
	device_destroy(renderer.device)
	// delete_context(&renderer.ctx)
}

renderer_render :: proc(renderer: ^Renderer) {
	cmd, err := begin_frame(renderer)
	if err != nil {
		return
	}

	begin_render_pass(renderer, cmd)

	pipeline := pipeline_manager_bind_pipeline(renderer.pipeline_manager, "main", cmd)

	scene_draw(&renderer.scene, cmd, pipeline.layout)

	end_render_pass(renderer, cmd)

	end_frame(renderer, cmd)
}

@(private = "file")
begin_frame :: proc(renderer: ^Renderer) -> (cmd: vk.CommandBuffer, err: Render_Error) {
	frame := frame_manager_get_frame(&renderer.swapchain_manager.frame_manager)

	frame_wait(frame, renderer.device)

	_, acquire_err := swapchain_acquire_next_image(
		&renderer.swapchain_manager,
		frame.sync.image_available,
	)

	if acquire_err != nil {
		if acquire_err == .Out_Of_Date {
			// TODO handle resize in this
			renderer_handle_resizing(renderer)
		}
		return {}, acquire_err
	}

	_ = vk_check(
		vk.ResetFences(renderer.device.logical_device.ptr, 1, &frame.sync.in_flight_fence),
		"Error reseting in_flight_fence",
	)

	cmd = frame.commands.primary_buffer
	_ = vk_check(vk.ResetCommandBuffer(cmd, {}), "Error reseting command buffer")


	_ = vk_check(
		vk.BeginCommandBuffer(cmd, &vk.CommandBufferBeginInfo{sType = .COMMAND_BUFFER_BEGIN_INFO}),
		"Failed to begin command buffer",
	)

	return cmd, nil
}

@(private = "file")
end_frame :: proc(renderer: ^Renderer, cmd: vk.CommandBuffer) {
	image, _ := swapchain_manager_get_current_image_info(renderer.swapchain_manager)
	image_transition(
		cmd,
		{
			image = image,
			old_layout = .COLOR_ATTACHMENT_OPTIMAL,
			new_layout = .PRESENT_SRC_KHR,
			src_stage = {.COLOR_ATTACHMENT_OUTPUT},
			dst_stage = {.BOTTOM_OF_PIPE},
			src_access = {.COLOR_ATTACHMENT_WRITE},
			dst_access = {},
		},
	)

	_ = vk_check(vk.EndCommandBuffer(cmd), "Failed to end command buffer")

	if result := swapchain_manager_submit_command_buffers(&renderer.swapchain_manager, {cmd});
	   result != nil {
		if result == .Suboptimal_Surface || result == .Out_Of_Date {
			// TODO: handle resizing
			renderer_handle_resizing(renderer)
		}
	}
}

@(private = "file")
begin_render_pass :: proc(renderer: ^Renderer, cmd: vk.CommandBuffer) {
	image, image_view := swapchain_manager_get_current_image_info(renderer.swapchain_manager)

	image_transition(
		cmd,
		{
			image = image,
			old_layout = .UNDEFINED,
			new_layout = .COLOR_ATTACHMENT_OPTIMAL,
			src_stage = {.TOP_OF_PIPE},
			dst_stage = {.COLOR_ATTACHMENT_OUTPUT},
			src_access = {},
			dst_access = {.COLOR_ATTACHMENT_WRITE},
		},
	)

	color_attachment := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = image_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = vk.ClearValue{color = vk.ClearColorValue{float32 = {0.01, 0.01, 0.01, 1.0}}},
	}

	extent := renderer.swapchain_manager.extent
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
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
end_render_pass :: proc(renderer: ^Renderer, cmd: vk.CommandBuffer) {
	vk.CmdEndRendering(cmd)
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
