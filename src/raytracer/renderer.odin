package raytracer

import "core:log"
import "core:math/linalg"
import "core:slice"
import "core:thread"
_ :: log

Renderer :: struct {
	camera:                                     ^Camera,
	scene:                                      ^Scene,
	image:                                      ^Image,
	image_horizontal_iter, image_vertical_iter: [dynamic]u32,
	accumulation_data:                          []Vec4,
	image_data:                                 []u32,
	frame_index:                                u32,
	accumulate:                                 bool,
}

Hit_Payload :: struct {
	hit_distance:                 f32,
	world_position, world_normal: Vec3,
	object_index:                 int,
}

renderer_render :: proc(renderer: ^Renderer) {
	if renderer.frame_index == 1 {
		slice.fill(renderer.accumulation_data, 0)
	}

	pool: thread.Pool
	thread.pool_init(&pool, context.temp_allocator, 8)
	defer thread.pool_destroy(&pool)

	for y in 0 ..< renderer.image.height {
		thread.pool_add_task(&pool, context.temp_allocator, proc(task: thread.Task) {
				renderer := cast(^Renderer)task.data
				y := u32(task.user_index)

				for x in 0 ..< renderer.image.width {
					color := renderer_per_pixel(renderer^, x, y)
					renderer.accumulation_data[x + y * renderer.image.width] += color

					accumulated_color := renderer.accumulation_data[x + y * renderer.image.width]
					accumulated_color /= f32(renderer.frame_index)

					accumulated_color = linalg.clamp(accumulated_color, 0, 1)
					renderer.image_data[x + y * renderer.image.width] = convert_to_rgba(
						accumulated_color,
					)
				}
			}, renderer, int(y))
	}

	thread.pool_start(&pool)
	thread.pool_finish(&pool)

	image_set_data(renderer.image^, raw_data(renderer.image_data[:]))

	if renderer.accumulate {
		renderer.frame_index += 1
	}
}

renderer_on_resize :: proc(renderer: ^Renderer, width, height: u32) {

	if renderer.image != nil {
		if renderer.image.width == width && renderer.image.height == height {
			return
		}

		image_resize(renderer.image, width, height)
	} else {
		renderer.image = new(Image)
		image_init(renderer.image, width, height)
	}

	delete(renderer.image_data)
	renderer.image_data = make([]u32, width * height)

	delete(renderer.accumulation_data)
	renderer.accumulation_data = make([]Vec4, width * height)

	resize(&renderer.image_horizontal_iter, width)
	resize(&renderer.image_vertical_iter, height)

	for i in 0 ..< width {
		renderer.image_horizontal_iter[i] = i
	}

	for i in 0 ..< height {
		renderer.image_vertical_iter[i] = i
	}

	renderer.frame_index = 1
}

renderer_per_pixel :: proc(renderer: Renderer, x, y: u32) -> Vec4 {
	ray := Ray {
		origin    = renderer.camera.position,
		direction = renderer.camera.ray_directions[x + y * renderer.image.width],
	}
	light: Vec3
	contribution := Vec3{1.0, 1.0, 1.0}

	bounces := 5
	for _ in 0 ..< bounces {
		payload := renderer_trace_ray(renderer, ray)
		if payload.hit_distance < 0 {
			//sky_color := Vec3{0.6, 0.7, 0.9}
			//light += sky_color * contribution
			break
		}

		sphere := renderer.scene.spheres[payload.object_index]
		material := renderer.scene.materials[sphere.material_index]

		contribution *= material.albedo
		light += material_get_emission(material)

		ray.origin = payload.world_position + payload.world_normal * 0.0001
		ray.direction = linalg.normalize(payload.world_normal + random_unit_disk())
	}
	return Vec4{light.x, light.y, light.z, 1.0}
}

renderer_trace_ray :: proc(renderer: Renderer, ray: Ray) -> Hit_Payload {
	closest_sphere := -1
	interval := empty_interval()
	hit_distance := interval.max

	for &sphere, i in renderer.scene.spheres {
		if distance, did_hit := sphere_hit(
			sphere,
			ray,
			Interval{min = interval.min, max = hit_distance},
		); did_hit {
			hit_distance = distance
			closest_sphere = i
		}
	}

	if closest_sphere < 0 {
		return renderer_miss(renderer, ray)
	}
	return renderer_closest_hit(renderer, ray, hit_distance, u32(closest_sphere))
}

renderer_closest_hit :: proc(
	renderer: Renderer,
	ray: Ray,
	hit_distance: f32,
	object_index: u32,
) -> Hit_Payload {
	payload := Hit_Payload {
		hit_distance = hit_distance,
		object_index = int(object_index),
	}

	sphere := renderer.scene.spheres[object_index]
	origin := ray.origin - sphere.position
	payload.world_position = origin + ray.direction * hit_distance
	payload.world_normal = linalg.normalize(payload.world_position)

	payload.world_position += sphere.position

	return payload
}

renderer_miss :: proc(renderer: Renderer, ray: Ray) -> Hit_Payload {
	return Hit_Payload{hit_distance = -1}
}

renderer_reset_frame_index :: proc(renderer: ^Renderer) {
	renderer.frame_index = 1
}
