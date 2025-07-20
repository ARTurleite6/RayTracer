package raytracer

import vk "vendor:vulkan"

Image_Set :: struct {
	images:      []Image,
	image_views: []vk.ImageView,
}

@(require_results)
make_image_set :: proc(
	ctx: ^Vulkan_Context,
	format: vk.Format,
	extent: vk.Extent2D,
	frames_in_flight: int,
	allocator := context.allocator,
) -> (
	is: Image_Set,
) {
	is.images = make([]Image, frames_in_flight, allocator)
	is.image_views = make([]vk.ImageView, frames_in_flight, allocator)

	cmd := device_begin_single_time_commands(ctx.device, ctx.device.command_pool)
	defer device_end_single_time_commands(ctx.device, ctx.device.command_pool, cmd)
	for &img, idx in is.images {
		image_init(&img, ctx, format, extent)
		image_view_init(&is.image_views[idx], img, ctx)

		image_transition_layout_stage_access(
			cmd,
			img.handle,
			.UNDEFINED,
			.GENERAL,
			{.ALL_COMMANDS},
			{.ALL_COMMANDS},
			{},
			{},
			format = img.format,
		)
	}

	return is
}

image_set_destroy :: proc(ctx: ^Vulkan_Context, is: ^Image_Set, allocator := context.allocator) {
	for &img, idx in is.images {
		image_destroy(&img, ctx^)
		image_view_destroy(is.image_views[idx], ctx^)
	}

	delete(is.images, allocator)
	delete(is.image_views, allocator)
}

image_set_get :: proc(is: ^Image_Set, frame: int) -> ^Image {
	return &is.images[frame]
}

image_set_get_view :: proc(is: Image_Set, frame: int) -> vk.ImageView {
	return is.image_views[frame]
}
