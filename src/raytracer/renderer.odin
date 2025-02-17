package raytracer

Renderer :: struct {
	ctx:         ^Context,
	frame_index: u32,
	command_pool: Command_Pool,
}

make_renderer :: proc(ctx: ^Context) -> Renderer {
	return {ctx = ctx, frame_index = 0}
}

delete_renderer :: proc(renderer: Renderer) {
    delete_command_pool(renderer.command_pool)
}
