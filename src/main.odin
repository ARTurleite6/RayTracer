package main

import "core:fmt"
import "raytracer/camera"
import "raytracer/hittable"
import mat "raytracer/material"

create_world :: proc() -> hittable.Hittable_List {
	material_ground := mat.Lambertian{{0.8, 0.8, 0.0}}
	material_center := mat.Lambertian{{0.1, 0.2, 0.5}}
	material_left := mat.Dieletric{1.50}
	material_bubble := mat.Dieletric{1.0 / 1.50}
	material_right := mat.Metal{{0.8, 0.6, 0.2}, 1.0}

	world: hittable.Hittable_List
	hittable.hittable_list_init(&world)
	defer hittable.hittable_list_destroy(world)


	sphere: hittable.Sphere
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
	aspect_ratio := 16.0 / 9.0
	image_width := 400

	image_height := int(f64(image_width) / aspect_ratio)
	image_height = (image_height < 1) ? 1 : image_height

	//Camera 
	c: camera.Camera
	camera.init(
		&c,
		image_width = image_width,
		image_height = image_height,
		look_at = {0, 0, -1},
		up = {0, 1, 0},
		center = {0, 0, 0},
		samples_per_pixel = 100,
		defocus_angle = 0.0,
		focal_distance = 3.4,
	)

	world := create_world()
	if err := camera.render(c, world, "image.ppm"); err != nil {
		fmt.eprintln(err)
		return
	}
}
