package raytracer

Renderer :: struct {}

@(require_results)
renderer_init :: proc(renderer: ^Renderer) -> Error {
	return nil
}

renderer_destroy :: proc(renderer: Renderer) {
}
