package raytracer

Scene :: struct {
	spheres:   [dynamic]Sphere,
	meshes:    [dynamic]Mesh,
	materials: [dynamic]Material,
}

scene_init :: proc(scene: ^Scene, allocator := context.allocator) {
	context.allocator = allocator
	scene.spheres = make([dynamic]Sphere)
	scene.meshes = make([dynamic]Mesh)
	scene.materials = make([dynamic]Material)
}

scene_destroy :: proc(scene: ^Scene) {
	delete(scene.spheres)
	delete(scene.meshes)
	delete(scene.materials)
	scene.spheres = nil
	scene.meshes = nil
	scene.materials = nil
}
