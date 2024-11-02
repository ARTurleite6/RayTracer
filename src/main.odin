package main

import "base:runtime"
import "core:c"
// import "core:fmt"
import "core:log"
import imgui "external:odin-imgui"
import imgui_glfw "external:odin-imgui/imgui_impl_glfw"
import imgui_opengl "external:odin-imgui/imgui_impl_opengl3"
import "raytracer"
import gl "vendor:OpenGL"
import "vendor:glfw"
_ :: gl

DISABLE_DOCKING :: #config(DISABLE_DOCKING, false)

Application :: struct {
	window:          glfw.WindowHandle,
	renderer:        raytracer.Renderer,
	scene:           raytracer.Scene,
	camera:          raytracer.Camera,
	viewport_height: u32,
	viewport_width:  u32,
}

create_application :: proc(window: glfw.WindowHandle) -> Application {
	application := Application {
		window = window,
		renderer = raytracer.Renderer{frame_index = 1, accumulate = true},
	}

	raytracer.camera_init(&application.camera, 45, 0.1, 100)

	application.scene.spheres = make([dynamic]raytracer.Sphere)
	application.scene.materials = make([dynamic]raytracer.Material)

	ground: raytracer.Material
	raytracer.material_init(&ground, {0.8, 0.8, 0.0})

	center: raytracer.Material
	raytracer.material_init(&center, {0.1, 0.2, 0.5})

	light: raytracer.Material
	raytracer.material_init(
		&light,
		{0.1, 0.2, 0.5},
		emission_color = {1, 1, 1},
		emission_power = 2,
	)

	append(&application.scene.materials, ground, center, light)

	{
		sphere: raytracer.Sphere
		sphere.position = {0.0, 0.0, 0.0}
		sphere.radius = 1.0
		sphere.material_index = 1
		append(&application.scene.spheres, sphere)
	}

	{
		sphere: raytracer.Sphere
		sphere.position = {2.0, 0.0, 0.0}
		sphere.radius = 1.0
		sphere.material_index = 2
		append(&application.scene.spheres, sphere)
	}

	{
		sphere: raytracer.Sphere
		sphere.position = {0.0, -101.0, 0.0}
		sphere.radius = 100.0
		sphere.material_index = 0
		append(&application.scene.spheres, sphere)
	}

	return application
}

on_update :: proc(application: ^Application, last_render_time: f32) {
	if raytracer.camera_update(&application.camera, application.window, last_render_time) {
		raytracer.renderer_reset_frame_index(&application.renderer)
	}
}

on_render :: proc(application: ^Application, last_render_time: f64) {
	imgui.Begin("Settings")
	imgui.Text("Last render: %.3fms", last_render_time)
	if imgui.Button("Render") {
		render(application)
	}

	if imgui.Button("Reset") {
		raytracer.renderer_reset_frame_index(&application.renderer)
	}

	if imgui.Checkbox("Accumulate", &application.renderer.accumulate) {
		raytracer.renderer_reset_frame_index(&application.renderer)
	}

	imgui.End()

	imgui.Begin("Scene")
	for &sphere, i in application.scene.spheres {
		imgui.PushIDInt(i32(i))

		imgui.DragFloat3("Position", &sphere.position, 0.1)
		imgui.DragFloat("Radius", &sphere.radius, 0.1)
		imgui.DragInt("Material", cast(^i32)&sphere.material_index)
		imgui.Separator()

		imgui.PopID()
	}

	for &material, i in application.scene.materials {
		imgui.PushIDInt(i32(i))

		imgui.ColorEdit3("Albedo", &material.albedo)
		imgui.DragFloat("Roughness", &material.roughness, 0.05, 0.0, 1.0)
		imgui.DragFloat("Metallic", &material.metallic, 0.05, 0.0, 1.0)
		imgui.ColorEdit3("Emission Color", &material.emission_color)
		imgui.DragFloat("Emission Power", &material.emission_power, 0.05, 0.0, 100)
		imgui.Separator()

		imgui.PopID()
	}

	imgui.End()

	imgui.PushStyleVarImVec2(.WindowPadding, imgui.Vec2{0, 0})
	imgui.Begin("Viewport")

	application.viewport_width = u32(imgui.GetContentRegionAvail().x)
	application.viewport_height = u32(imgui.GetContentRegionAvail().y)

	image := application.renderer.image
	if image != nil {
		imgui.Text(
			"size = %d x %d",
			application.renderer.image.width,
			application.renderer.image.width,
		)

		imgui.Image(
			raytracer.image_descriptor(image^),
			{f32(image.width), f32(image.height)},
			{0, 1},
			{1, 0},
		)
	}

	imgui.End()
	imgui.PopStyleVar()

	render(application)
}

render :: proc(application: ^Application) {
	application.renderer.camera = &application.camera
	application.renderer.scene = &application.scene

	raytracer.camera_on_resize(
		&application.camera,
		application.viewport_width,
		application.viewport_height,
	)

	raytracer.renderer_on_resize(
		&application.renderer,
		application.viewport_width,
		application.viewport_height,
	)

	raytracer.renderer_render(&application.renderer)
}


main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	clear_color := imgui.Vec4{0.45, 0.55, 0.60, 1.00}

	glfw.SetErrorCallback(proc "c" (error: c.int, description: cstring) {
		context = runtime.default_context()
		// fmt.eprintf("GLFW Error %d: %s\n", error, description)
	})

	if !glfw.Init() {
		log.fatal("Error initializing glfw")
		return
	}
	defer glfw.Terminate()

	glsl_version: cstring = "#version 150"
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 1)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	when ODIN_OS == .Darwin {
		glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, gl.TRUE)
	}

	window := glfw.CreateWindow(1280, 720, "RayTracing", nil, nil)
	if window == nil {
		log.fatal("Error initializing glfw")
		return
	}
	defer glfw.DestroyWindow(window)
	glfw.MakeContextCurrent(window)
	glfw.SwapInterval(1)
	gl.load_up_to(4, 1, glfw.gl_set_proc_address)

	imgui.CHECKVERSION()
	imgui.CreateContext()
	defer imgui.DestroyContext()
	io := imgui.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard}

	when !DISABLE_DOCKING {
		io.ConfigFlags += {.DockingEnable, .ViewportsEnable}

		style := imgui.GetStyle()
		style.WindowRounding = 0
		style.Colors[imgui.Col.WindowBg].w = 1
	}

	imgui.StyleColorsDark()

	imgui_glfw.InitForOpenGL(window, true)
	defer imgui_glfw.Shutdown()
	imgui_opengl.Init(glsl_version)
	defer imgui_opengl.Shutdown()

	application := create_application(window)

	last_frame: f64
	for !glfw.WindowShouldClose(window) {
		free_all(context.temp_allocator)
		current_frame := glfw.GetTime()
		delta_time := current_frame - last_frame
		last_frame = current_frame

		glfw.PollEvents()

		imgui_opengl.NewFrame()
		imgui_glfw.NewFrame()
		imgui.NewFrame()

		on_update(&application, f32(delta_time))

		on_render(&application, delta_time)

		imgui.Render()

		viewport := imgui.GetMainViewport()
		imgui.SetNextWindowPos(viewport.Pos)
		imgui.SetNextWindowSize(viewport.Size)
		imgui.SetNextWindowViewport(viewport._ID)

		width, height := glfw.GetFramebufferSize(window)
		gl.Viewport(0, 0, width, height)
		gl.ClearColor(
			clear_color.x * clear_color.w,
			clear_color.y * clear_color.w,
			clear_color.z * clear_color.w,
			clear_color.w,
		)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		imgui_opengl.RenderDrawData(imgui.GetDrawData())

		when !DISABLE_DOCKING {
			backup_current_window := glfw.GetCurrentContext()
			imgui.UpdatePlatformWindows()
			imgui.RenderPlatformWindowsDefault()
			glfw.MakeContextCurrent(backup_current_window)
		}

		glfw.SwapBuffers(window)
	}

	// if err := camera.render(c, tree, "image.ppm"); err != nil {
	// 	fmt.eprintln(err)
	// 	return
	// }
}
