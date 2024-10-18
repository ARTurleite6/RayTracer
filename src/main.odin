package main

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:time"
import "raytracer/camera"
import "raytracer/color"
import "raytracer/hittable"
import mat "raytracer/material"
import "raytracer/utils"

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

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

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
	hittable.bvh_init(&tree, world.hittables[:], 10, .HLBVH)
	log.infof("Time constructing tree: %v", time.tick_since(begin))

	if err := camera.render(c, tree, "image.ppm"); err != nil {
		fmt.eprintln(err)
		return
	}
}
