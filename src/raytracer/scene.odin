package raytracer

Scene :: struct {
	primitives: #soa[dynamic]Primitive,
	materials:  [dynamic]Material,
}

scene_init :: proc(scene: ^Scene, allocator := context.allocator) {
	context.allocator = allocator
	scene.primitives = make(#soa[dynamic]Primitive)
	scene.materials = make([dynamic]Material)
}

scene_destroy :: proc(scene: ^Scene) {
	delete(scene.primitives)
	delete(scene.materials)
	scene.primitives = nil
	scene.materials = nil
}
