package interval

Interval :: struct {
	min, max: f64,
}

between :: proc(a: Interval, b: Interval) -> (i: Interval) {
	i.min = a.min <= b.min ? a.min : b.min
	i.max = a.max >= b.max ? a.max : b.max
	return
}

surrounds :: proc(interval: Interval, value: f64) -> bool {
	return interval.min < value && value < interval.max
}
