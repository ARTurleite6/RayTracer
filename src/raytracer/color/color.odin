package color

import "../utils"
import "core:fmt"
import "core:math"
import "core:os"

Color :: utils.Vec3

write :: proc(color: Color, out: os.Handle) {
	gamma_color := color_linear_to_gamma(color)

	rbyte := int(255.999 * gamma_color[0])
	gbyte := int(255.999 * gamma_color[1])
	bbyte := int(255.999 * gamma_color[2])

	fmt.fprintln(out, "%d %d %d", rbyte, gbyte, bbyte)
}

color_linear_to_gamma :: proc(linear_color: Color) -> Color {
	return {
		linear_component_to_gamma(linear_color.r),
		linear_component_to_gamma(linear_color.g),
		linear_component_to_gamma(linear_color.b),
	}
}

linear_component_to_gamma :: proc(linear_component: f32) -> f32 {
	return linear_component > 0 ? math.sqrt(linear_component) : 0
}
