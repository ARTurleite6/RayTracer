package raytracer

import "core:strings"
import imgui "external:odin-imgui"
import imgui_glfw "external:odin-imgui/imgui_impl_glfw"
import imgui_vulkan "external:odin-imgui/imgui_impl_vulkan"
import vk "vendor:vulkan"

UI_Context :: struct {
	pool: vk.DescriptorPool,
}

UI_Stage :: struct {
	using base: Render_Stage,
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

ui_stage_init :: proc(stage: ^UI_Stage, name: string, allocator := context.allocator) {
	render_stage_init(stage, name, stage, allocator)
}

ui_stage_render :: proc(
	graph: Render_Graph,
	ui_stage: ^UI_Stage,
	cmd: vk.CommandBuffer,
	image_index: u32,
	render_data: Render_Data,
) {
	image_transition(
		cmd,
		image = graph.swapchain.images[image_index],
		old_layout = .UNDEFINED,
		new_layout = .COLOR_ATTACHMENT_OPTIMAL,
		src_stage = {.TOP_OF_PIPE},
		dst_stage = {.COLOR_ATTACHMENT_OUTPUT},
		src_access = {},
		dst_access = {.COLOR_ATTACHMENT_WRITE},
	)

	begin_render_pass(graph, ui_stage, cmd, image_index)

	imgui_vulkan.NewFrame()
	imgui_glfw.NewFrame()
	imgui.NewFrame()

	if imgui.BeginMainMenuBar() {
		if imgui.BeginMenu("File") {
			if imgui.MenuItem("Exit", "Q") {
				window_set_should_close(render_data.renderer.window^)
			}
			imgui.EndMenu()
		}

		imgui.EndMainMenuBar()
	}

	render_statistics(render_data.renderer.scene)

	render_scene_properties(
		&render_data.renderer.scene,
		render_data.descriptor_manager,
		render_data.renderer.ctx.device,
	)


	imgui.Render()
	imgui_vulkan.RenderDrawData(imgui.GetDrawData(), cmd)

	end_render_pass(graph, cmd, image_index)

	image_transition(
		cmd,
		image = graph.swapchain.images[image_index],
		old_layout = .COLOR_ATTACHMENT_OPTIMAL,
		new_layout = .PRESENT_SRC_KHR,
		src_stage = {.COLOR_ATTACHMENT_OUTPUT},
		dst_stage = {.BOTTOM_OF_PIPE},
		src_access = {.COLOR_ATTACHMENT_WRITE},
		dst_access = {},
	)
}

@(private = "file")
render_scene_properties :: proc(
	scene: ^Scene,
	descriptor_manager: ^Descriptor_Set_Manager,
	device: ^Device,
) {
	if imgui.Begin("Scene Properties") {
		if imgui.CollapsingHeader("Materials", {.DefaultOpen}) {
			@(static) selected_material := -1
			if imgui.BeginListBox("##MaterialList", {0, 100}) {
				for material, i in scene.materials {
					is_selected := selected_material == i
					if imgui.Selectable(
						strings.clone_to_cstring(material.name, context.temp_allocator),
						is_selected,
					) {
						selected_material = i
					}

					if is_selected {
						imgui.SetItemDefaultFocus()
					}
				}
				imgui.EndListBox()
			}
			if selected_material >= 0 && selected_material < len(scene.materials) {
				material := &scene.materials[selected_material]

				imgui.Separator()
				// imgui.Text("Albedo")
				albedo := material.albedo
				if imgui.ColorPicker3("Albedo", &albedo) {
					material.albedo = albedo

					scene_update_material(scene, selected_material, device, descriptor_manager)
				}
			}
		}


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

				position := object.transform.position
				if imgui.DragFloat3("Position", &position, 0.01) {
					object_update_position(object, position)
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
