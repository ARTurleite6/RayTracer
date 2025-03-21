package raytracer

import "core:container/queue"
import "core:slice"
import "core:strings"
import imgui "external:odin-imgui"
import imgui_glfw "external:odin-imgui/imgui_impl_glfw"
import imgui_vulkan "external:odin-imgui/imgui_impl_vulkan"
import vk "vendor:vulkan"

UI_Context :: struct {
	pool:              vk.DescriptorPool,
	selected_object:   int,
	selected_material: int,

	// New material creation
	new_material_name: [256]byte,
}

ui_context_init :: proc(ctx: ^UI_Context, device: ^Device, window: Window) {
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

	imgui.CHECKVERSION()
	imgui.CreateContext()

	io := imgui.GetIO()
	io.ConfigFlags += {.NavEnableGamepad, .NavEnableKeyboard, .DockingEnable}
	style := imgui.GetStyle()
	style.WindowRounding = 0
	style.Colors[imgui.Col.WindowBg] = 1
	imgui.StyleColorsDark()

	imgui_vulkan.LoadFunctions(
		proc "c" (name: cstring, vulkan_instance: rawptr) -> vk.ProcVoidFunction {
			return vk.GetInstanceProcAddr(cast(vk.Instance)vulkan_instance, name)
		},
		device.instance.ptr,
	)

	imgui_glfw.InitForVulkan(window.handle, true)
	@(static) format: vk.Format = .B8G8R8A8_SRGB
	init_info := imgui_vulkan.InitInfo {
		Instance = device.instance.ptr,
		PhysicalDevice = device.physical_device.ptr,
		Device = device.logical_device.ptr,
		Queue = device.graphics_queue,
		DescriptorPool = ctx.pool,
		MinImageCount = 2,
		ImageCount = 2,
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

	ctx.selected_object = -1
	ctx.selected_material = -1
}

ui_context_destroy :: proc(ctx: ^UI_Context, device: ^Device) {
	imgui_vulkan.Shutdown()
	imgui_glfw.Shutdown()
	imgui.DestroyContext()
	vk.DestroyDescriptorPool(device.logical_device.ptr, ctx.pool, nil)
}

ui_render :: proc(renderer: ^Renderer) {
	scene := renderer.scene
	cmd := &renderer.current_cmd
	ctx := &renderer.ctx
	ctx_transition_swapchain_image(
		ctx^,
		cmd^,
		old_layout = .UNDEFINED,
		new_layout = .COLOR_ATTACHMENT_OPTIMAL,
		src_stage = {.TOP_OF_PIPE},
		dst_stage = {.COLOR_ATTACHMENT_OUTPUT},
		src_access = {},
		dst_access = {.COLOR_ATTACHMENT_WRITE},
	)

	info := ctx_get_swapchain_render_pass(ctx^, load_op = .LOAD)
	command_buffer_begin_render_pass(cmd, &info)

	imgui_vulkan.NewFrame()
	imgui_glfw.NewFrame()
	imgui.NewFrame()

	if imgui.BeginMainMenuBar() {
		if imgui.BeginMenu("File") {
			if imgui.MenuItem("Exit", "Q") {
				window_set_should_close(renderer.window)
			}
			imgui.EndMenu()
		}

		imgui.EndMainMenuBar()
	}

	render_statistics(scene^)

	render_scene_properties(renderer, renderer.ctx.device)

	imgui.EndFrame()

	imgui.Render()

	imgui.UpdatePlatformWindows()
	imgui.RenderPlatformWindowsDefault()

	imgui_vulkan.RenderDrawData(imgui.GetDrawData(), cmd.buffer)

	command_buffer_end_render_pass(cmd)

	ctx_transition_swapchain_image(
		ctx^,
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
render_scene_properties :: proc(renderer: ^Renderer, device: ^Device) {
	if imgui.Begin("Scene Properties") {
		render_object_properties(renderer)
		render_material_properties(renderer)
	}
	imgui.End()
}

@(private = "file")
render_material_properties :: proc(renderer: ^Renderer) {
	scene := renderer.scene
	if imgui.CollapsingHeader("Materials", {.DefaultOpen}) {
		imgui.Text("New material")
		new_material_name := renderer.ui_ctx.new_material_name[:]
		imgui.InputText(
			"Material name",
			strings.unsafe_string_to_cstring(string(new_material_name)),
			len(renderer.ui_ctx.new_material_name),
		)
		if imgui.Button("Submit", {100, 0}) {
			material := Material {
				name = strings.clone(string(new_material_name)),
			}

			scene_add_material(scene, material)
			queue.push_back(&renderer.ui_events, New_Material{})

			slice.zero(new_material_name)
		}

		imgui.Separator()

		selected_material := &renderer.ui_ctx.selected_material
		if imgui.BeginListBox("##MaterialList", {0, 100}) {
			for material, i in scene.materials {
				is_selected := selected_material^ == i

				if imgui.Selectable(
					strings.clone_to_cstring(material.name, context.temp_allocator),
					is_selected,
				) {
					selected_material^ = i
				}

				if is_selected {
					imgui.SetItemDefaultFocus()
				}
			}

			imgui.EndListBox()
		}
		if selected_material^ >= 0 && selected_material^ < len(scene.materials) {
			material := &scene.materials[selected_material^]

			imgui.Separator()

			update_material := false
			new_albedo := material.albedo
			if imgui.ColorPicker3("Albedo", &new_albedo, {}) {
				material.albedo = new_albedo
				update_material = true
			}

			new_emission_color := material.emission_color
			if imgui.ColorPicker3("Emission Color", &new_emission_color) {
				material.emission_color = new_emission_color
				update_material = true
			}

			new_emission_power := material.emission_power
			if imgui.DragFloat("Emission Power", &new_emission_power) {
				material.emission_power = new_emission_power
				update_material = true
			}

			if imgui.Button("Delete Material", {100, 0}) {
				queue.push_back(&renderer.ui_events, Update_Material{})
				scene_delete_material(scene, selected_material^)
			}

			if update_material {
				scene_update_material(scene, selected_material^, material^)
				queue.push_back(&renderer.ui_events, Update_Material{})
			}
		}
	}
}

@(private = "file")
render_object_properties :: proc(renderer: ^Renderer) {
	scene := renderer.scene
	if imgui.CollapsingHeader("Objects", {.DefaultOpen}) {
		selected_object := &renderer.ui_ctx.selected_object
		if imgui.BeginListBox("##ObjectList", {0, 100}) {
			for object, i in scene.objects {
				is_selected := selected_object^ == i

				if imgui.Selectable(
					strings.clone_to_cstring(object.name, context.temp_allocator),
					is_selected,
				) {
					selected_object^ = i
				}

				if is_selected {
					imgui.SetItemDefaultFocus()
				}
			}

			imgui.EndListBox()
		}
		if selected_object^ >= 0 && selected_object^ < len(scene.objects) {
			object := &scene.objects[selected_object^]

			imgui.Separator()
			imgui.Text("Transform")

			new_position := object.transform.position
			if imgui.DragFloat3("Position", &new_position, 0.01) {
				scene_update_object_position(scene, selected_object^, new_position)
				queue.push_back(
					&renderer.ui_events,
					Update_Object_Transform{object_index = selected_object^},
				)
			}

			imgui.Separator()
			// Addding one to the material so it appears nicer to the user
			new_material := i32(object.material_index + 1)
			if imgui.InputInt("Material", &new_material, 1) {
				scene_update_object_material(
					renderer.scene,
					selected_object^,
					int(new_material - 1),
				)
				queue.push(
					&renderer.ui_events,
					Update_Object_Material{object_index = selected_object^},
				)
			}
		}
	}
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
