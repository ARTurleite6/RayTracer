package raytracer

import "core:strings"
import "core:container/queue"
import imgui "external:odin-imgui"
import imgui_glfw "external:odin-imgui/imgui_impl_glfw"
import imgui_vulkan "external:odin-imgui/imgui_impl_vulkan"
import vk "vendor:vulkan"

UI_Context :: struct {
	pool: vk.DescriptorPool,
}

ui_context_init :: proc(ctx: ^UI_Context, device: ^Device, window: Window, format: vk.Format) {
	descriptor_pool_init(
		&ctx.pool,
		device,
		{
			{.SAMPLER, 1000},
			{.COMBINED_IMAGE_SAMPLER, 1000},
			{.SAMPLED_IMAGE, 1000},
			{.STORAGE_IMAGE, 1000},
			{.UNIFORM_TEXEL_BUFFER, 1000},
			{.STORAGE_TEXEL_BUFFER, 1000},
			{.UNIFORM_BUFFER, 1000},
			{.STORAGE_BUFFER, 1000},
			{.UNIFORM_BUFFER_DYNAMIC, 1000},
			{.STORAGE_BUFFER_DYNAMIC, 1000},
			{.INPUT_ATTACHMENT, 1000},
		},
		1000,
		{.FREE_DESCRIPTOR_SET},
	)

	imgui.CreateContext()
	imgui_vulkan.LoadFunctions(
		proc "c" (name: cstring, vulkan_instance: rawptr) -> vk.ProcVoidFunction {
			return vk.GetInstanceProcAddr(cast(vk.Instance)vulkan_instance, name)
		},
		device.instance.ptr,
	)

	imgui_glfw.InitForVulkan(window.handle, true)
	format := format
	init_info := imgui_vulkan.InitInfo {
		Instance = device.instance.ptr,
		PhysicalDevice = device.physical_device.ptr,
		Device = device.logical_device.ptr,
		Queue = device.graphics_queue,
		DescriptorPool = ctx.pool,
		MinImageCount = 3,
		ImageCount = 3,
		UseDynamicRendering = true,
		PipelineRenderingCreateInfo = {
			sType = .PIPELINE_RENDERING_CREATE_INFO,
			colorAttachmentCount = 1,
			pColorAttachmentFormats = &format,
		},
		MSAASamples = ._1,
	}
	imgui_vulkan.Init(&init_info)
	imgui_vulkan.CreateFontsTexture()
}

ui_context_destroy :: proc(ctx: ^UI_Context, device: ^Device) {
	imgui_vulkan.Shutdown()
	vk.DestroyDescriptorPool(device.logical_device.ptr, ctx.pool, nil)
}

ui_render :: proc(ctx: Vulkan_Context, cmd: ^Command_Buffer, renderer: ^Renderer) {
	ctx_transition_swapchain_image(
		ctx,
		cmd^,
		old_layout = .UNDEFINED,
		new_layout = .COLOR_ATTACHMENT_OPTIMAL,
		src_stage = {.TOP_OF_PIPE},
		dst_stage = {.COLOR_ATTACHMENT_OUTPUT},
		src_access = {},
		dst_access = {.COLOR_ATTACHMENT_WRITE},
	)

	info := ctx_get_swapchain_render_pass(ctx, load_op = .LOAD)
	command_buffer_begin_render_pass(cmd, &info)

	imgui_vulkan.NewFrame()
	imgui_glfw.NewFrame()
	imgui.NewFrame()

	if imgui.BeginMainMenuBar() {
		if imgui.BeginMenu("File") {
			if imgui.MenuItem("Exit", "Q") {
				window_set_should_close(renderer.window^)
			}
			imgui.EndMenu()
		}

		imgui.EndMainMenuBar()
	}

	render_statistics(renderer.scene)

	render_scene_properties(renderer, renderer.ctx.device)


	imgui.Render()
	imgui_vulkan.RenderDrawData(imgui.GetDrawData(), cmd.buffer)

	command_buffer_end_render_pass(cmd)

	ctx_transition_swapchain_image(
		ctx,
		cmd^,
		old_layout = .COLOR_ATTACHMENT_OPTIMAL,
		new_layout = .PRESENT_SRC_KHR,
		src_stage = {.COLOR_ATTACHMENT_OUTPUT},
		dst_stage = {.BOTTOM_OF_PIPE},
		src_access = {.COLOR_ATTACHMENT_WRITE},
		dst_access = {},
	)
}

@(private = "file")
render_scene_properties :: proc(renderer: ^Renderer,  device: ^Device) {
	scene := &renderer.scene
	if imgui.Begin("Scene Properties") {
		if imgui.CollapsingHeader("Objects", {}) {
			@(static) selected_object := -1

			if imgui.BeginListBox("##ObjectList", {0, 100}) {
				for object, i in scene.objects {
					is_selected := selected_object == i

					if imgui.Selectable(
						strings.clone_to_cstring(object.name, context.temp_allocator),
						is_selected,
					) {
						selected_object = i
					}

					if is_selected {
						imgui.SetItemDefaultFocus()
					}
				}

				imgui.EndListBox()
			}
			if selected_object >= 0 && selected_object < len(scene.objects) {
				object := &scene.objects[selected_object]

				imgui.Separator()
				imgui.Text("Transform")

				new_position := object.transform.position
				if imgui.DragFloat3("Position", &new_position, 0.01) {
					queue.push(&renderer.events, Scene_Object_Update_Position {
						object_index = selected_object,
						new_position = new_position,
					})
				}

				imgui.Separator()
				new_material := i32(object.material_index + 1)
				if imgui.InputInt("Material", &new_material, 1) {
					queue.push(&renderer.events, Scene_Object_Material_Change {
						object_index = selected_object,
						new_material_index = int(new_material) - 1,
					})
				}
			}
		}

	}
	imgui.End()
}

@(private = "file")
render_statistics :: proc(scene: Scene) {
	io := imgui.GetIO()

	if imgui.Begin("Performance") {
		imgui.Text(
			"Application average %.3f ms/frame, (%.1f FPS)",
			1000.0 / io.Framerate,
			io.Framerate,
		)

		imgui.PlotLines("Frame Times", &io.DeltaTime, 120, 0, nil, 0.0, 0.050, {0., 80}, 4)

		if imgui.CollapsingHeader("Detailed Statistics") {
			imgui.Text("ImGui:")
			imgui.Text("- Vertices: %d", io.MetricsRenderVertices)
			imgui.Text("- Indices: %d", io.MetricsRenderIndices)
			imgui.Text("- Draw calls: %d", io.MetricsRenderWindows)

			imgui.Separator()
			imgui.Text("Renderer:")
			imgui.Text("- Objects: %d", len(scene.objects))
			imgui.Text("- Meshes: %d", len(scene.meshes))
		}
	}
	imgui.End()
}
