package hittable_test

import "../../../src/raytracer/hittable"
import "../../../src/raytracer/hittable/aabb"
import "../../../src/raytracer/interval"
import "core:log"
import "core:testing"

@(test)
empty_bvh_ok :: proc(t: ^testing.T) {
	using hittable

	world: Hittable_List
	hittable.hittable_list_init(&world)
	defer hittable_list_destroy(&world)

	bvh: BVH
	hittable.bvh_init(&bvh, world.hittables[:])
	defer bvh_destroy(&bvh)

	testing.expect_value(t, len(bvh.nodes), 0)
	testing.expect_value(t, bvh.root, nil)
}

@(test)
single_item_bvh_ok :: proc(t: ^testing.T) {
	using hittable

	sphere: Sphere
	sphere_init(&sphere, {}, 100, {})

	world: Hittable_List
	hittable_list_init(&world)
	hittable_list_add(&world, sphere)
	defer hittable_list_destroy(&world)

	bvh: BVH
	bvh_init(&bvh, world.hittables[:])
	defer bvh_destroy(&bvh)

	testing.expect_value(t, len(bvh.nodes), 1)
	root_node, has_root := bvh.root.(int)
	testing.expect_value(t, has_root, true)
	testing.expect_value(t, bvh.nodes[root_node].left, nil)
	testing.expect_value(t, bvh.nodes[root_node].right, nil)
	testing.expect_value(t, bvh.nodes[root_node].box, sphere.box)
}

@(test)
three_item_bvh_ok :: proc(t: ^testing.T) {
	using hittable

	sphere: Sphere

	world: Hittable_List
	hittable_list_init(&world)
	defer hittable_list_destroy(&world)

	sphere_init(&sphere, {100, 0, -100}, 50, {})
	hittable_list_add(&world, sphere)
	sphere_init(&sphere, {}, 100, {})
	hittable_list_add(&world, sphere)
	sphere_init(&sphere, {}, 5, {})
	hittable_list_add(&world, sphere)

	bvh: BVH
	bvh_init(&bvh, world.hittables[:])
	defer bvh_destroy(&bvh)

	testing.expect_value(t, len(bvh.nodes), 5)
	root_node, has_root := bvh.root.(int)
	testing.expect_value(t, has_root, true)
	testing.expect_value(t, bvh.nodes[root_node].left.(int), 1)
	testing.expect_value(t, bvh.nodes[root_node].right.(int), 2)
	testing.expect_value(
		t,
		bvh.nodes[root_node].box,
		aabb.AABB {
			x = interval.Interval{min = -100, max = 150},
			y = interval.Interval{min = -100, max = 100},
			z = interval.Interval{min = -150, max = 100},
		},
	)
}

@(test)
multiple_element_ok :: proc(t: ^testing.T) {
	using hittable

	// Create the world using the provided create_world procedure
	world := create_world()
	defer hittable_list_destroy(&world)

	// Create BVH from the world
	bvh: BVH
	bvh_init(&bvh, world.hittables[:])
	defer bvh_destroy(&bvh)

	// Test basic properties of the BVH
	testing.expect(t, len(bvh.nodes) > 0, "BVH should have nodes")
	root_node, has_root := bvh.root.(int)
	testing.expect(t, has_root, "BVH should have a root node")

	// Test the root node's bounding box
	root_box := bvh.nodes[root_node].box
	testing.expect(t, root_box.x.min < root_box.x.max, "Root box X interval should be valid")
	testing.expect(t, root_box.y.min < root_box.y.max, "Root box Y interval should be valid")
	testing.expect(t, root_box.z.min < root_box.z.max, "Root box Z interval should be valid")

	// Test that the root box contains all spheres
	for sphere in world.hittables {
		if s, ok := sphere.(Sphere); ok {
			testing.expect(
				t,
				aabb.contains(root_box, s.box),
				"Root box should contain all spheres",
			)
		}
	}

	// Test that leaf nodes correspond to actual objects
	leaf_count := 0
	for node in bvh.nodes {
		if object, is_leaf := node.object.(^hittable.Hittable);
		   node.left == nil && node.right == nil && is_leaf {
			leaf_count += 1
			found := false
			for sphere in world.hittables {
				if s, ok := sphere.(Sphere); ok {
					if node.box == s.box {
						found = true
						break
					}
				}
			}
			testing.expect(t, found, "Each leaf node should correspond to an object in the world")
		}
	}
	testing.expect(
		t,
		leaf_count == len(world.hittables),
		"Number of leaf nodes should match number of objects",
	)
}

create_world :: proc() -> hittable.Hittable_List {
	sphere: hittable.Sphere
	world: hittable.Hittable_List
	hittable.hittable_list_init(&world)

	hittable.sphere_init(&sphere, center = {0, -100.5, -1}, radius = 100, material = {})
	hittable.hittable_list_add(&world, sphere)
	hittable.sphere_init(&sphere, center = {0, 0, -1.2}, radius = 0.5, material = {})
	hittable.hittable_list_add(&world, sphere)
	hittable.sphere_init(&sphere, center = {-1.0, 0, -1}, radius = 0.5, material = {})
	hittable.hittable_list_add(&world, sphere)
	hittable.sphere_init(&sphere, center = {-1.0, 0, -1}, radius = 0.4, material = {})
	hittable.hittable_list_add(&world, sphere)
	hittable.sphere_init(&sphere, center = {1.0, 0, -1}, radius = 0.5, material = {})
	hittable.hittable_list_add(&world, sphere)

	return world
}
