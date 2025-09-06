package raytracer

import "core:mem"

align_up :: proc(x, align: u32) -> u32 {
	return u32(mem.align_forward_uint(uint(x), uint(align)))
}
