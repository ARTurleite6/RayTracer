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
	builder := &Descriptor_Pool_Builder{}
	descriptor_pool_builder_init(builder, device)
	descriptor_pool_builder_set_max_sets(builder, 1000)
	descriptor_pool_builder_add_pool_size(builder, .SAMPLER, 1000)
	descriptor_pool_builder_add_pool_size(builder, .COMBINED_IMAGE_SAMPLER, 1000)
	descriptor_pool_builder_add_pool_size(builder, .SAMPLED_IMAGE, 1000)
	descriptor_pool_builder_add_pool_size(builder, .STORAGE_IMAGE, 1000)
	descriptor_pool_builder_add_pool_size(builder, .UNIFORM_TEXEL_BUFFER, 1000)
	descriptor_pool_builder_add_pool_size(builder, .STORAGE_TEXEL_BUFFER, 1000)
	descriptor_pool_builder_add_pool_size(builder, .UNIFORM_BUFFER, 1000)
	descriptor_pool_builder_add_pool_size(builder, .STORAGE_BUFFER, 1000)
	descriptor_pool_builder_add_pool_size(builder, .UNIFORM_BUFFER_DYNAMIC, 1000)
	descriptor_pool_builder_add_pool_size(builder, .STORAGE_BUFFER_DYNAMIC, 1000)
	descriptor_pool_builder_add_pool_size(builder, .INPUT_ATTACHMENT, 1000)
	descriptor_pool_builder_set_flags(builder, {.FREE_DESCRIPTOR_SET})
	ctx.pool, _ = descriptor_pool_build(builder)

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

	render_scene_properties(render_data.renderer.scene)


	imgui.Render()
	imgui_vulkan.RenderDrawData(imgui.GetDrawData(), cmd)
}

@(private = "file")
render_scene_properties :: proc(scene: Scene) {
	if imgui.Begin("Scene Properties") {
		if imgui.CollapsingHeader("Objects", {.DefaultOpen}) {
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
