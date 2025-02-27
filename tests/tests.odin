package tests

import "../src/raytracer"
import "core:testing"

@(test)
test_load_obj :: proc(t: ^testing.T) {
	scene, err := raytracer.load_obj_file("objects/quad.obj")
	expected_vertices := []raytracer.Vec4 {
		{-1.0, 1.0, 0.0, 1},
		{-1.0, -1.0, 0.0, 1},
		{1.0, -1.0, 0.0, 1},
		{1.0, 1.0, 0.0, 1},
		{-1.0, 1.0, -0.1, 1},
		{-1.0, -1.0, -0.1, 1},
		{1.0, -1.0, -0.1, 1},
		{1.0, 1.0, -0.1, 1},
		{-1.0, 1.0, -0.2, 1},
		{-1.0, -1.0, -0.2, 1},
		{1.0, -1.0, -0.2, 1},
		{1.0, 1.0, -0.2, 1},
		{-1.0, 1.0, -0.3, 1},
		{-1.0, -1.0, -0.3, 1},
		{1.0, -1.0, -0.3, 1},
		{1.0, 1.0, -0.3, 1},
	}

	expected_objects := []raytracer.Object {
		{name = "Quad1"},
		{name = "Quad2"},
		{name = "Quad3"},
		{name = "Quad4"},
	}

	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(scene.vertices), len(expected_vertices))
	for vert, i in expected_vertices {
		testing.expect_value(t, scene.vertices[i], vert)
	}

	testing.expect_value(t, len(scene.objects), len(expected_objects))
	for obj, i in expected_objects {
		testing.expect_value(t, scene.objects[i], obj)
	}
}
