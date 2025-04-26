package raytracer

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import imgui "external:odin-imgui"
import imgui_glfw "external:odin-imgui/imgui_impl_glfw"
import imgui_vulkan "external:odin-imgui/imgui_impl_vulkan"
import vk "vendor:vulkan"
_ :: log

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
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

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
	if !imgui.CollapsingHeader("Materials", {.DefaultOpen}) {
		return
	}

	// ============= MATERIAL CREATION SECTION =============
	imgui.PushID("Creation")
	{
		imgui.Text("Create New Material")

		new_material_name := renderer.ui_ctx.new_material_name[:]
		imgui.InputText(
			"Material Name",
			strings.unsafe_string_to_cstring(string(new_material_name)),
			len(renderer.ui_ctx.new_material_name),
		)

		name_valid := len(strings.trim_space(string(new_material_name))) > 0
		if !name_valid {
			imgui.BeginDisabled()
		}

		if imgui.Button("Create Material", {150, 0}) {
			material := Material {
				name      = strings.clone(string(new_material_name)),
				albedo    = {0.8, 0.8, 0.8},
				roughness = 0.5,
				metallic  = 0.0,
			}
			scene_add_material(scene, material)
			slice.zero(new_material_name)
			renderer.ui_ctx.selected_material = len(scene.materials) - 1
		}

		if !name_valid {
			imgui.EndDisabled()
			if imgui.IsItemHovered() {
				imgui.SetTooltip("Material name cannot be empty")
			}
		}

		imgui.Separator()
	}
	imgui.PopID()

	// ============= MATERIAL SELECTION SECTION =============
	imgui.PushID("Selection")
	{
		imgui.Text("Material List")
		selected_material := &renderer.ui_ctx.selected_material

		// Material filtering
		@(static) filter: [128]byte
		imgui.InputTextWithHint(
			"##FilterMaterials",
			"Filter materials...",
			strings.unsafe_string_to_cstring(string(filter[:])),
			len(filter),
		)
		filter_str := strings.to_lower(
			strings.truncate_to_byte(string(filter[:]), 0),
			context.temp_allocator,
		)

		if imgui.BeginListBox("##MaterialList", {0, 150}) {
			render_material_list(scene, filter_str, selected_material)
			imgui.EndListBox()
		}

		if len(scene.materials) == 0 {
			imgui.TextColored({1, 0.5, 0, 1}, "No materials available. Create one above.")
		}

		imgui.Separator()
	}
	imgui.PopID()

	// ============= MATERIAL EDITING SECTION =============
	selected_material := renderer.ui_ctx.selected_material
	if selected_material >= 0 && selected_material < len(scene.materials) {
		imgui.PushID("Editing")
		render_material_editor(&renderer.ui_ctx, scene, selected_material)
		imgui.PopID()
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

@(private = "file")
render_material_list :: proc(scene: ^Scene, filter_str: string, selected_material: ^int) {
	for material, i in scene.materials {
		// Skip if doesn't match filter
		if len(filter_str) > 0 &&
		   !strings.contains_any(
				   strings.to_lower(material.name, context.temp_allocator),
				   filter_str,
			   ) {
			continue
		}
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

		// Show preview color indicator
		imgui.SameLine(imgui.GetWindowWidth() - 30)
		imgui.ColorButton(
			"##preview",
			{material.albedo.x, material.albedo.y, material.albedo.z, 1.0},
			{.NoTooltip},
			{20, 10},
		)
	}
}

@(private = "file")
render_material_editor :: proc(ui_ctx: ^UI_Context, scene: ^Scene, mat_index: int) {
	material := &scene.materials[mat_index]

	imgui.Text("Editing: %s", strings.clone_to_cstring(material.name, context.temp_allocator))
	imgui.Spacing()

	update_material := false

	// ---- Properties Tabs ----
	if imgui.BeginTabBar("MaterialProperties") {
		update_material |= render_surface_properties_tab(material)
		update_material |= render_emission_properties_tab(material)
		imgui.EndTabBar()
	}

	imgui.Spacing()
	imgui.Separator()
	imgui.Spacing()

	// ---- Actions ----
	render_material_actions(ui_ctx, scene, mat_index, material)

	if update_material {
		scene_update_material(scene, mat_index, material^)
	}
}

@(private = "file")
render_surface_properties_tab :: proc(material: ^Material) -> bool {
	if !imgui.BeginTabItem("Surface") {
		return false
	}
	defer imgui.EndTabItem()

	update := false

	update |= imgui.ColorEdit3("Albedo", &material.albedo, {.Float, .PickerHueWheel})

	update |= imgui.SliderFloat("Roughness", &material.roughness, 0.0, 1.0)
	imgui.SameLine(0, 5)
	help_marker("Controls the micro-surface roughness. 0 = perfectly smooth, 1 = very rough")

	update |= imgui.SliderFloat("Metallic", &material.metallic, 0.0, 1.0)
	imgui.SameLine(0, 5)
	help_marker("Controls how metallic the material is. 0 = dielectric, 1 = metallic")

	return update
}

@(private = "file")
render_emission_properties_tab :: proc(material: ^Material) -> bool {
	if !imgui.BeginTabItem("Emission") {
		return false
	}
	defer imgui.EndTabItem()

	update := false

	update |= imgui.ColorEdit3(
		"Emission Color",
		&material.emission_color,
		{.Float, .PickerHueWheel},
	)

	update |= imgui.SliderFloat("Emission Power", &material.emission_power, 0.0, 20.0)
	imgui.SameLine(0, 5)
	help_marker("Controls the intensity of light emitted by this material")

	return update
}

@(private = "file")
render_material_actions :: proc(
	ui_ctx: ^UI_Context,
	scene: ^Scene,
	mat_index: int,
	material: ^Material,
) {
	// Delete Button
	if imgui.Button("Delete Material", {150, 0}) {
		imgui.OpenPopup("Delete Material?")
	}

	// Material usage info
	material_in_use, usage_count := get_material_usage(scene, mat_index)
	if material_in_use {
		imgui.SameLine()
		imgui.TextColored({1, 0.5, 0, 1}, "Used by %d object(s)", usage_count)
	}

	// Confirmation Popup
	render_delete_material_popup(ui_ctx, scene, mat_index, material, material_in_use, usage_count)

	// Duplicate Button
	imgui.SameLine()
	if imgui.Button("Duplicate", {120, 0}) {
		new_material := material^
		new_material.name = fmt.aprintf("%s (Copy)", material.name)
		scene_add_material(scene, new_material)
		ui_ctx.selected_material = len(scene.materials) - 1
	}
}

@(private = "file")
render_delete_material_popup :: proc(
	ui_ctx: ^UI_Context,
	scene: ^Scene,
	mat_index: int,
	material: ^Material,
	material_in_use: bool,
	usage_count: int,
) {
	if !imgui.BeginPopupModal("Delete Material?", nil, {.AlwaysAutoResize}) {
		return
	}
	defer imgui.EndPopup()

	imgui.Text(
		"Are you sure you want to delete '%s'?",
		strings.clone_to_cstring(material.name, context.temp_allocator),
	)

	if material_in_use {
		imgui.TextColored(
			{1, 0.5, 0, 1},
			"Warning: This material is used by %d object(s).",
			usage_count,
		)
	}

	imgui.Text("This operation cannot be undone.")
	imgui.Separator()

	if imgui.Button("Yes, Delete It", {140, 0}) {
		scene_delete_material(scene, mat_index)
		ui_ctx.selected_material = -1
		imgui.CloseCurrentPopup()
	}

	imgui.SameLine()
	if imgui.Button("Cancel", {140, 0}) {
		imgui.CloseCurrentPopup()
	}
}

@(private = "file")
get_material_usage :: proc(scene: ^Scene, mat_index: int) -> (in_use: bool, count: int) {
	for object in scene.objects {
		if object.material_index == mat_index {
			in_use = true
			count += 1
		}
	}
	return
}

@(private = "file")
help_marker :: proc(desc: string) {
	imgui.TextDisabled("(?)")
	if imgui.IsItemHovered() {
		imgui.BeginTooltip()
		imgui.PushTextWrapPos(imgui.GetFontSize() * 35.0)
		imgui.TextUnformatted(strings.clone_to_cstring(desc, context.temp_allocator))
		imgui.PopTextWrapPos()
		imgui.EndTooltip()
	}
}
