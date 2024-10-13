package interval

import "core:math"

Interval :: struct {
	min, max: f64,
}

empty :: proc() -> Interval {
	return {min = +math.INF_F64, max = -math.INF_F64}
}

contains :: proc(outer, inner: Interval) -> bool {
	return outer.min <= inner.min && inner.max <= outer.max
}

between :: proc(a: Interval, b: Interval) -> (i: Interval) {
	i.min = a.min <= b.min ? a.min : b.min
	i.max = a.max >= b.max ? a.max : b.max
	return
}

surrounds :: proc(interval: Interval, value: f64) -> bool {
	return interval.min < value && value < interval.max
}

size :: proc(i: Interval) -> f64 {
	return i.max - i.min
}
