package raytracer

import "core:log"
import "core:math"
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
	front_face:                   bool,
}

renderer_render :: proc(renderer: ^Renderer) {
	if renderer.frame_index == 1 {
		slice.fill(renderer.accumulation_data, 0)
	}

	pool: thread.Pool
	thread.pool_init(&pool, context.temp_allocator, 16)

	y_chunk_size := int(renderer.image.height / 16)
	x_chunk_size := int(renderer.image.width / 16)
	for y := 0; y < int(renderer.image.height); y += y_chunk_size {
		for x := 0; x < int(renderer.image.height); x += x_chunk_size {
			Task :: struct {
				renderer:  ^Renderer,
				outer_idx: int,
				inner_idx: int,
				outer_end: int,
				inner_end: int,
			}
			task := new(Task, context.temp_allocator)
			task.renderer = renderer
			task.outer_idx = y
			task.inner_idx = x
			task.outer_end = min(int(y + y_chunk_size), int(renderer.image.height))
			task.inner_end = min(int(x + x_chunk_size), int(renderer.image.width))

			thread.pool_add_task(&pool, context.allocator, proc(task: thread.Task) {
					context.allocator = task.allocator
					task_data := cast(^Task)task.data
					renderer := task_data.renderer

					for y in task_data.outer_idx ..< task_data.outer_end {
						for x in task_data.inner_idx ..< task_data.inner_end {
							x := u32(x)
							y := u32(y)

							color := renderer_per_pixel(renderer^, x, y)
							renderer.accumulation_data[x + y * renderer.image.width] += color

							accumulated_color :=
								renderer.accumulation_data[x + y * renderer.image.width]
							accumulated_color /= f32(renderer.frame_index)

							accumulated_color = linalg.clamp(accumulated_color, 0, 1)
							renderer.image_data[x + y * renderer.image.width] = convert_to_rgba(
								accumulated_color,
							)

						}
					}
				}, task)
		}
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
			sky_color := Vec3{0.6, 0.7, 0.9}
			light += sky_color * contribution
			break
		}

		mesh := renderer.scene.meshes[payload.object_index]
		context.user_index = payload.object_index
		material := renderer.scene.materials[mesh.material_index]

		light += material_get_emission(material)

		onb: ONB
		onb_init(&onb, payload.world_normal)
		wo := onb_world_to_local(onb, -ray.direction)

		f, pdf, wi := multi_brdf_sample(material, wo, random_vec2())
		if pdf == 0 {
			break
		}
		contribution *= f * wi.z / pdf
		ray.origin = payload.world_position + payload.world_normal * 0.0001
		ray.direction = onb_local_to_world(onb, wi)

	}
	return Vec4{light.x, light.y, light.z, 1.0}
}

renderer_trace_ray :: proc(renderer: Renderer, ray: Ray) -> Hit_Payload {
	hit_distance, closest_mesh, normal, _ := hit(
		renderer.scene.meshes[:],
		ray,
		Interval{min = 0, max = math.F32_MAX},
	)

	if closest_mesh < 0 {
		return renderer_miss(renderer, ray)
	}
	return renderer_closest_hit(renderer, ray, hit_distance, normal, u32(closest_mesh))
}

renderer_closest_hit :: proc(
	renderer: Renderer,
	ray: Ray,
	hit_distance: f32,
	normal: Vec3,
	object_index: u32,
) -> Hit_Payload {
	payload := Hit_Payload {
		hit_distance = hit_distance,
		object_index = int(object_index),
	}

	// mesh := renderer.scene.meshes[object_index]
	payload.world_position = ray.origin + ray.direction * hit_distance
	payload.world_normal = normal
	// payload.front_face = linalg.dot(-ray.direction, payload.world_normal) > 0
	// payload.world_normal = payload.front_face ? payload.world_normal : -payload.world_normal

	return payload
}

renderer_miss :: proc(renderer: Renderer, ray: Ray) -> Hit_Payload {
	return Hit_Payload{hit_distance = -1}
}

renderer_reset_frame_index :: proc(renderer: ^Renderer) {
	renderer.frame_index = 1
}
