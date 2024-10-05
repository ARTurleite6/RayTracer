package camera

import "../color"
import "../hittable"
import "../material/scatter"
import "../ray"
import "../utils"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"

MAX_DEPTH :: 50

Camera :: struct {
	image_width, image_height: int,
	samples_per_pixel:         int,
	center:                    utils.Vec3,
	pixel00_location:          utils.Vec3,
	pixel_delta_u:             utils.Vec3,
	pixel_delta_v:             utils.Vec3,
	defocus_disk_u:            utils.Vec3,
	defocus_disk_v:            utils.Vec3,
	defocus_angle:             f64,
}

init :: proc(
	camera: ^Camera,
	image_width, image_height: int,
	center: utils.Vec3,
	look_at: utils.Vec3,
	up: utils.Vec3,
	defocus_angle: f64,
	focal_distance: f64,
	vfov := 90.0,
	samples_per_pixel := 10,
) {
	camera.image_width = image_width
	camera.image_height = image_height
	camera.samples_per_pixel = samples_per_pixel
	camera.center = center
	camera.defocus_angle = defocus_angle

	//vectors
	dir := look_at - camera.center
	w := linalg.normalize(dir)
	u := linalg.normalize(linalg.cross(dir, up))
	v := linalg.cross(w, u)

	//viewport
	theta := linalg.to_radians(vfov)
	h := linalg.tan(theta / 2)
	viewport_height := 2.0 * f64(h) * focal_distance
	viewport_width := viewport_height * (f64(image_width) / f64(image_height))

	viewport_u := viewport_width * u
	viewport_v := viewport_height * v
	camera.pixel_delta_u = viewport_u / f64(image_width)
	camera.pixel_delta_v = viewport_v / f64(image_height)

	viewport_upper_left := camera.center + w * focal_distance - viewport_u / 2 - viewport_v / 2
	camera.pixel00_location =
		viewport_upper_left + 0.5 * (camera.pixel_delta_u + camera.pixel_delta_v)

	defocus_radius := focal_distance * linalg.tan(linalg.to_radians(defocus_angle / 2))
	camera.defocus_disk_u = u * defocus_radius
	camera.defocus_disk_v = v * defocus_radius
}

render :: proc(
	c: Camera,
	world: hittable.Hittable,
	filepath: string,
	random_generator := context.random_generator,
) -> os.Error {
	f := os.open(filepath, os.O_CREATE | os.O_RDWR) or_return
	defer os.close(f)
	pixel_sample_scale := 1.0 / f64(c.samples_per_pixel)

	fmt.fprintfln(f, "P3\n%d %d\n255", c.image_width, c.image_height)

	for j in 0 ..< c.image_height {
		for i in 0 ..< c.image_width {
			utils.progress_bar(j * c.image_width + i, c.image_width * c.image_height)

			pixel_color: utils.Vec3
			for _ in 0 ..< c.samples_per_pixel {
				r := get_ray(c, i, j)
				pixel_color += ray_color(r, world, MAX_DEPTH)
			}

			color.write(out = f, color = pixel_color * pixel_sample_scale)
		}
	}
	return nil
}

get_ray :: proc(c: Camera, i, j: int, generator := context.random_generator) -> ray.Ray {
	offset := utils.random_vec3(generator = generator) - 0.5
	pixel_sample :=
		c.pixel00_location +
		((f64(i) + offset.x) * c.pixel_delta_u) +
		((f64(j) + offset.y) * c.pixel_delta_v)

	ray_origin := c.defocus_angle <= 0 ? c.center : defocus_disk_sample(c)
	return {origin = ray_origin, direction = pixel_sample - ray_origin}
}

defocus_disk_sample :: proc(c: Camera) -> utils.Vec3 {
	p := utils.random_unit_disk()

	return c.center + (p[0] * c.defocus_disk_u) + (p[1] * c.defocus_disk_v)
}

ray_color :: proc(r: ray.Ray, ht: hittable.Hittable, depth: int) -> color.Color {
	if depth <= 0 {
		return {}
	}

	// Hittable
	if hit_record, hitted := hittable.hit(ht, r, {min = 0.001, max = math.F64_MAX}); hitted {
		if scattered, attenuation, has_scattered := scatter.scatter(
			hit_record.material,
			r,
			hit_record,
		); has_scattered {
			return attenuation * ray_color(scattered, ht, depth - 1)
		}

		return {}
	}

	// Background
	unit_direction := linalg.normalize(r.direction)
	a := 0.5 * (unit_direction.y + 1.0)
	return (1.0 - a) * color.Color{1.0, 1.0, 1.0} + a * color.Color{0.5, 0.7, 1.0}
}
