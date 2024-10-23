package hittable_test

import "../../../src/raytracer/color"
import "../../../src/raytracer/hittable"
import "../../../src/raytracer/hittable/aabb"
import "../../../src/raytracer/interval"
import mat "../../../src/raytracer/material"
import "../../../src/raytracer/utils"
import "core:log"
import "core:math/linalg"
import "core:mem/virtual"
import "core:slice"
import "core:testing"

@(test)
single_item_bvh_ok :: proc(t: ^testing.T) {
	using hittable
	defer free_all(context.temp_allocator)

	sphere: Sphere
	sphere_init(&sphere, {}, 100, {})

	world: Hittable_List
	hittable_list_init(&world)
	hittable_list_add(&world, sphere)
	defer hittable_list_destroy(&world)

	bvh: BVH
	bvh_init(&bvh, world.hittables[:], 10, .SAH, arena = context.allocator)
	defer bvh_destroy(&bvh)

	testing.expect_value(t, len(bvh.nodes), 1)
}

@(test)
three_items_bvh_ok :: proc(t: ^testing.T) {
	using hittable
	defer free_all(context.temp_allocator)

	sphere1: Sphere
	sphere_init(&sphere1, {-100, 0, 0}, 100, {})

	sphere2: Sphere
	sphere_init(&sphere2, {100, 0, 0}, 100, {})

	sphere3: Sphere
	sphere_init(&sphere3, {100, 0, -50}, 100, {})

	world: Hittable_List
	hittable_list_init(&world)
	hittable_list_add(&world, sphere1)
	hittable_list_add(&world, sphere2)
	hittable_list_add(&world, sphere3)
	defer hittable_list_destroy(&world)

	bvh: BVH
	bvh_init(&bvh, world.hittables[:], 1, .HLBVH, arena = context.allocator)
	defer bvh_destroy(&bvh)

	testing.expect_value(t, len(bvh.nodes), 5)
}

@(test)
test_world_bvh_ok :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	world := create_book_scene()
	defer hittable.hittable_list_destroy(&world)

	bvh: hittable.BVH

	before := slice.clone(world.hittables[:])
	delete(before)

	hittable.bvh_init(&bvh, world.hittables[:], 10, .HLBVH, arena = context.allocator)
	defer hittable.bvh_destroy(&bvh)

	all_equal := true
	for &ht in before {
		found := false
		for &an in bvh.primitives {
			an := an.(hittable.Sphere)
			ht := ht.(hittable.Sphere)
			if an == ht {
				found = true
				break
			}
		}

		if !found {
			all_equal = false
			break
		}
	}

	all_nodes_valid := true
	for &node in bvh.nodes {
		if node.n_primitives > 0 {
			for i in 0 ..< node.n_primitives {
				prim_index := node.offset + uint(i)
				if prim_index >= uint(len(bvh.primitives)) {
					all_nodes_valid = false
					break
				}
			}
		}
		if !all_nodes_valid {
			break
		}
	}
	testing.expect(t, all_nodes_valid, "Not all BVH nodes point to valid primitives")

	// Check if all primitives are referenced by at least one node
	referenced := make([]bool, len(bvh.primitives))
	defer delete(referenced)
	for &node in bvh.nodes {
		if node.n_primitives > 0 {
			for i in 0 ..< node.n_primitives {
				prim_index := node.offset + uint(i)
				if prim_index < uint(len(referenced)) {
					referenced[prim_index] = true
				}
			}
		}
	}
	all_referenced := true
	for ref in referenced {
		if !ref {
			all_referenced = false
			break
		}
	}
	testing.expect(t, all_referenced, "Not all primitives are referenced by BVH nodes")

	testing.expect_value(t, all_equal, true)
}

create_book_scene :: proc() -> hittable.Hittable_List {
	ground_material := mat.Lambertian {
		albedo = {0.5, 0.5, 0.5},
	}
	world: hittable.Hittable_List
	hittable.hittable_list_init(&world)
	sphere: hittable.Sphere
	hittable.sphere_init(
		&sphere,
		center = {0, -1000, 0},
		radius = 1000,
		material = ground_material,
	)
	hittable.hittable_list_add(&world, sphere)

	for i in -11 ..< 11 {
		for j in -11 ..< 11 {
			choose_mat := utils.random_double()
			center := utils.Vec3 {
				f32(i) + 0.9 * utils.random_double(),
				0.2,
				f32(j) + 0.9 * utils.random_double(),
			}

			if linalg.length(center - utils.Vec3{4, 0.2, 0}) > 0.9 {
				material: mat.Material
				if choose_mat < 0.8 {
					albedo: color.Color = utils.random_vec3() * utils.random_vec3()
					material = mat.Lambertian {
						albedo = albedo,
					}
				} else if choose_mat < 0.95 {
					albedo := utils.random_vec3(0.5, 1)
					fuzz := utils.random_double(0, 0.5)
					material = mat.Metal {
						albedo = albedo,
						fuzz   = fuzz,
					}
				} else {
					material = mat.Dieletric {
						refraction_index = 1.5,
					}
				}
				hittable.sphere_init(&sphere, center = center, radius = 0.2, material = material)
				hittable.hittable_list_add(&world, sphere)
			}
		}
	}

	hittable.sphere_init(
		&sphere,
		center = {0, 1, 0},
		radius = 1,
		material = mat.Dieletric{refraction_index = 1.5},
	)
	hittable.hittable_list_add(&world, sphere)

	hittable.sphere_init(
		&sphere,
		center = {-4, 1, 0},
		radius = 1,
		material = mat.Lambertian{albedo = {0.4, 0.2, 0.1}},
	)
	hittable.hittable_list_add(&world, sphere)

	hittable.sphere_init(
		&sphere,
		center = {4, 1, 0},
		radius = 1,
		material = mat.Metal{albedo = {0.7, 0.6, 0.5}, fuzz = 0},
	)
	hittable.hittable_list_add(&world, sphere)
	return world
}


