package main

import "base:runtime"
import "core:c"
import gl "vendor:OpenGL"
import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:mem/virtual"
import "core:time"
import imgui "external:odin-imgui"
import imgui_glfw "external:odin-imgui/imgui_impl_glfw"
import imgui_opengl "external:odin-imgui/imgui_impl_opengl3"
import "raytracer/camera"
import "raytracer/color"
import "raytracer/hittable"
import mat "raytracer/material"
import "raytracer/utils"
import "vendor:glfw"
_ :: gl

create_book_scene :: proc() -> hittable.Hittable_List {
	ground_material := mat.Lambertian {
		albedo = {0.5, 0.5, 0.5},
	}
	world: hittable.Hittable_List
	hittable.hittable_list_init(&world)
	sphere: hittable.Sphere
	hittable.sphere_init(
		&sphere,
		center = {0, -1000, 0},
		radius = 1000,
		material = ground_material,
	)
	hittable.hittable_list_add(&world, sphere)

	for i in -11 ..< 11 {
		for j in -11 ..< 11 {
			choose_mat := utils.random_double()
			center := utils.Vec3 {
				f64(i) + 0.9 * utils.random_double(),
				0.2,
				f64(j) + 0.9 * utils.random_double(),
			}

			if linalg.length(center - utils.Vec3{4, 0.2, 0}) > 0.9 {
				material: mat.Material
				if choose_mat < 0.8 {
					albedo: color.Color = utils.random_vec3() * utils.random_vec3()
					material = mat.Lambertian {
						albedo = albedo,
					}
				} else if choose_mat < 0.95 {
					albedo := utils.random_vec3(0.5, 1)
					fuzz := utils.random_double(0, 0.5)
					material = mat.Metal {
						albedo = albedo,
						fuzz   = fuzz,
					}
				} else {
					material = mat.Dieletric {
						refraction_index = 1.5,
					}
				}
				hittable.sphere_init(&sphere, center = center, radius = 0.2, material = material)
				hittable.hittable_list_add(&world, sphere)
			}
		}
	}

	hittable.sphere_init(
		&sphere,
		center = {0, 1, 0},
		radius = 1,
		material = mat.Dieletric{refraction_index = 1.5},
	)
	hittable.hittable_list_add(&world, sphere)

	hittable.sphere_init(
		&sphere,
		center = {-4, 1, 0},
		radius = 1,
		material = mat.Lambertian{albedo = {0.4, 0.2, 0.1}},
	)
	hittable.hittable_list_add(&world, sphere)

	hittable.sphere_init(
		&sphere,
		center = {4, 1, 0},
		radius = 1,
		material = mat.Metal{albedo = {0.7, 0.6, 0.5}, fuzz = 0},
	)
	hittable.hittable_list_add(&world, sphere)
	return world
}

create_world :: proc() -> hittable.Hittable_List {
	material_ground := mat.Lambertian{{0.8, 0.8, 0.0}}
	material_center := mat.Lambertian{{0.1, 0.2, 0.5}}
	material_left := mat.Dieletric{1.50}
	material_bubble := mat.Dieletric{1.0 / 1.50}
	material_right := mat.Metal{{0.8, 0.6, 0.2}, 1.0}


	sphere: hittable.Sphere
	world: hittable.Hittable_List
	hittable.hittable_list_init(&world)

	hittable.sphere_init(
		&sphere,
		center = {0, -100.5, -1},
		radius = 100,
		material = material_ground,
	)
	hittable.hittable_list_add(&world, sphere)
	hittable.sphere_init(&sphere, center = {0, 0, -1.2}, radius = 0.5, material = material_center)
	hittable.hittable_list_add(&world, sphere)
	hittable.sphere_init(&sphere, center = {-1.0, 0, -1}, radius = 0.5, material = material_left)
	hittable.hittable_list_add(&world, sphere)
	hittable.sphere_init(&sphere, center = {-1.0, 0, -1}, radius = 0.4, material = material_bubble)
	hittable.hittable_list_add(&world, sphere)
	hittable.sphere_init(&sphere, center = {1.0, 0, -1}, radius = 0.5, material = material_right)
	hittable.hittable_list_add(&world, sphere)


	return world
}

render_scene_image :: proc() {

	aspect_ratio := 16.0 / 9.0
	image_width := 1200

	image_height := int(f64(image_width) / aspect_ratio)
	image_height = (image_height < 1) ? 1 : image_height

	//Camera
	c: camera.Camera
	camera.init(
		&c,
		image_width = image_width,
		image_height = image_height,
		vfov = 20,
		look_at = {0, 0, 0},
		up = {0, 1, 0},
		center = {13, 2, 3},
		samples_per_pixel = 1,
		defocus_angle = 0.6,
		focal_distance = 10,
	)

	world := create_book_scene()
	defer hittable.hittable_list_destroy(&world)

	begin := time.tick_now()
	tree: hittable.BVH

	arena: virtual.Arena
	if err := virtual.arena_init_growing(&arena); err != nil {
		log.fatal("Error creating the arena allocator, reason:", err)
		return
	}
	defer virtual.arena_destroy(&arena)
	allocator := virtual.arena_allocator(&arena)

	hittable.bvh_init(&tree, world.hittables[:], 10, .HLBVH, arena = allocator)
	free_all(context.temp_allocator)
	log.infof("Time constructing tree: %v", time.tick_since(begin))


}

render_ui :: proc() {
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
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 2)
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
	gl.load_up_to(3, 2, glfw.gl_set_proc_address)

	imgui.CHECKVERSION()
	imgui.CreateContext()
	defer imgui.DestroyContext()
	io := imgui.GetIO()
	io.ConfigFlags = {.NavEnableKeyboard}

	imgui.StyleColorsDark()

	imgui_glfw.InitForOpenGL(window, true)
	defer imgui_glfw.Shutdown()
	imgui_opengl.Init(glsl_version)
	defer imgui_opengl.Shutdown()

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		imgui_opengl.NewFrame()
		imgui_glfw.NewFrame()
		imgui.NewFrame()

		imgui.Begin("Basic window")
        imgui.Text("Hello from another window!")
        imgui.End()

		imgui.Render()
		width, height := glfw.GetFramebufferSize(window)
		gl.Viewport(0, 0, width, height)
		gl.ClearColor(clear_color.x * clear_color.w, clear_color.y * clear_color.w, clear_color.z * clear_color.w, clear_color.w)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		imgui_opengl.RenderDrawData(imgui.GetDrawData())

		glfw.SwapBuffers(window)
	}

	// if err := camera.render(c, tree, "image.ppm"); err != nil {
	// 	fmt.eprintln(err)
	// 	return
	// }
}
