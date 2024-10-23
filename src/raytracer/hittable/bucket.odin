package hittable

import "aabb"
import "base:intrinsics"

N_BUCKETS :: 12

Bucket_Info :: struct {
	count:  int,
	bounds: aabb.AABB,
}

min_cost_bucket :: proc(
	primitive_infos: []$T,
	centroid_bounds, scene_bounds: aabb.AABB,
	dim: uint,
) -> (
	min_cost: f32,
	bucket: uint,
) {

	buckets := create_buckets(primitive_infos, centroid_bounds, dim)
	return calculate_min_cost(buckets, scene_bounds)
}

@(private = "file")
@(require_results)
create_buckets :: proc(
	primitive_infos: []$T,
	centroid_bounds: aabb.AABB,
	dim: uint,
) -> [N_BUCKETS]Bucket_Info {
	buckets: [N_BUCKETS]Bucket_Info

	for &pr in primitive_infos {
		b := int(N_BUCKETS * offset(pr, centroid_bounds, dim))
		if b == N_BUCKETS do b -= 1
		buckets[b].count += 1
		buckets[b].bounds = aabb.merge(buckets[b].bounds, pr.bounds)
	}
	return buckets
}

@(private = "file")
@(require_results)
offset :: proc {
	primitive_offset,
	node_offset,
}

@(private = "file")
@(require_results)
primitive_offset :: proc(
	pr: BVH_Primitive_Info,
	centroid_bounds: aabb.AABB,
	dim: uint,
) -> f32 {
	return aabb.offset(centroid_bounds, pr.centroid)[dim]
}

@(private = "file")
@(require_results)
node_offset :: proc(
	tr: BVH_Build_Node,
	centroid_bounds: aabb.AABB,
	dim: uint,
) -> f32{
	centroid := aabb.centroid(tr.bounds)
	return aabb.offset(centroid_bounds, centroid)[dim]
}


@(private = "file")
@(require_results)
calculate_min_cost :: proc(
	buckets: [N_BUCKETS]Bucket_Info,
	scene_bounds: aabb.AABB,
) -> (
	min_cost: f32,
	bucket: uint,
) {
	cost: [N_BUCKETS - 1]f32
	for i in 0 ..< N_BUCKETS - 1 {
		b0, b1 := aabb.empty(), aabb.empty()
		count0, count1: int
		for j in 0 ..= i {
			b0 = aabb.merge(b0, buckets[j].bounds)
			count0 += buckets[j].count
		}

		for j in (i + 1) ..< N_BUCKETS {
			b1 = aabb.merge(b1, buckets[j].bounds)
			count1 += buckets[j].count
		}

		cost[i] =
			0.125 +
			(f32(count0) * aabb.surface_area(b0) + f32(count1) * aabb.surface_area(b1)) /
				aabb.surface_area(scene_bounds)
	}

	min_cost = cost[0]
	min_cost_split_bucket: uint = 0
	for i in 1 ..< N_BUCKETS - 1 {
		if cost[i] < min_cost {
			min_cost = cost[i]
			min_cost_split_bucket = uint(i)
		}
	}

	return min_cost, min_cost_split_bucket
}
