package raytracer

import "core:math"

Interval :: struct {
	min, max: f32,
}

empty_interval :: proc() -> Interval {
	return {min = -math.INF_F32, max = +math.INF_F32}
}

interval_contains :: proc(outer, inner: Interval) -> bool {
	return outer.min <= inner.min && inner.max <= outer.max
}

interval_between :: proc(a: Interval, b: Interval) -> (i: Interval) {
	i.min = a.min <= b.min ? a.min : b.min
	i.max = a.max >= b.max ? a.max : b.max
	return
}

interval_surrounds :: proc(interval: Interval, value: f32) -> bool {
	return interval.min < value && value < interval.max
}

interval_size :: proc(i: Interval) -> f32 {
	return i.max - i.min
}
