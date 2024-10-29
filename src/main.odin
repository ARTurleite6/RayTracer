package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:time"
import imgui "external:odin-imgui"
import imgui_glfw "external:odin-imgui/imgui_impl_glfw"
import imgui_opengl "external:odin-imgui/imgui_impl_opengl3"
import "raytracer"
import gl "vendor:OpenGL"
import "vendor:glfw"
_ :: gl

Application :: struct {
	renderer:        raytracer.Renderer,
	scene:           raytracer.Scene,
	camera:          raytracer.Camera,
	viewport_height: u32,
	viewport_width:  u32,
}

create_application :: proc() -> Application {
	application := Application {
		renderer = raytracer.Renderer{frame_index = 1, accumulate = true},
	}

	raytracer.camera_init(&application.camera, 45, 0.1, 100)

	application.scene.spheres = make([dynamic]raytracer.Sphere)
	application.scene.materials = make([dynamic]raytracer.Material)

	pink_sphere := raytracer.Material {
		albedo    = {1, 0, 1},
		roughness = 0,
	}
	blue_sphere := raytracer.Material {
		albedo    = {0.2, 0.3, 1.0},
		roughness = 0.1,
	}

	orange_sphere := raytracer.Material {
		albedo         = {0.8, 0.5, 0.2},
		roughness      = 0.1,
		emission_color = {0.8, 0.5, 0.2},
		emission_power = 2,
	}

	append(&application.scene.materials, pink_sphere, blue_sphere, orange_sphere)

	{
		sphere: raytracer.Sphere
		sphere.position = {0.0, 0.0, 0.0}
		sphere.radius = 1.0
		sphere.material_index = 0
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
		sphere.material_index = 1
		append(&application.scene.spheres, sphere)
	}

	return application
}

render_ui :: proc(application: ^Application, last_render_time: f64) {
	imgui.Begin("Settings")
	imgui.Text("Last render: %.3fms", last_render_time)
	if imgui.Button("Render") {
		render(application)
	}

	if imgui.Button("Reset") {
		raytracer.renderer_reset_frame_index(&application.renderer)
	}

	imgui.Checkbox("Accumulate", &application.renderer.accumulate)

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
		fmt.eprintf("GLFW Error %d: %s\n", error, description)
	})

	if !glfw.Init() {
		log.fatal("Error initializing glfw")
		return
	}
	defer glfw.Terminate()

	when ODIN_OS == .Darwin {
		glsl_version: cstring = "#version 150"
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 1)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
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

	imgui.StyleColorsDark()

	imgui_glfw.InitForOpenGL(window, true)
	defer imgui_glfw.Shutdown()
	imgui_opengl.Init(glsl_version)
	defer imgui_opengl.Shutdown()

	application := create_application()

	start := time.now()
	for !glfw.WindowShouldClose(window) {
		frame_time := time.now()
		last_render_time := time.duration_milliseconds(time.diff(start, frame_time))
		start = frame_time

		glfw.PollEvents()

		imgui_opengl.NewFrame()
		imgui_glfw.NewFrame()
		imgui.NewFrame()

		width, height := glfw.GetFramebufferSize(window)
		gl.Viewport(0, 0, width, height)
		gl.ClearColor(
			clear_color.x * clear_color.w,
			clear_color.y * clear_color.w,
			clear_color.z * clear_color.w,
			clear_color.w,
		)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		render_ui(&application, last_render_time)

		imgui.Render()

		imgui_opengl.RenderDrawData(imgui.GetDrawData())

		glfw.SwapBuffers(window)
	}

	// if err := camera.render(c, tree, "image.ppm"); err != nil {
	// 	fmt.eprintln(err)
	// 	return
	// }
}
