package raytracer

import "core:log"
import imgui "external:odin-imgui"
import gl "vendor:OpenGL"

Image :: struct {
	width, height, texture: u32,
}

image_init :: proc(image: ^Image, width, height: u32) {
	gl.GenTextures(1, &image.texture)
	gl.BindTexture(gl.TEXTURE_2D, image.texture)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RGBA8,
		i32(width),
		i32(height),
		0,
		gl.RGBA,
		gl.UNSIGNED_BYTE,
		nil,
	)

	gl.BindTexture(gl.TEXTURE_2D, 0)

	image.width, image.height = width, height
}

image_descriptor :: proc(image: Image) -> imgui.TextureID {
	return cast(rawptr)(uintptr(image.texture))
}

image_resize :: proc(image: ^Image, width, height: u32) {
	gl.BindTexture(gl.TEXTURE_2D, image.texture)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RGBA8,
		i32(width),
		i32(height),
		0,
		gl.RGBA,
		gl.UNSIGNED_BYTE,
		nil,
	)

	gl.BindTexture(gl.TEXTURE_2D, 0)

	image.width, image.height = width, height
}

image_set_data :: proc(image: Image, data: rawptr) {
	gl.BindTexture(gl.TEXTURE_2D, image.texture)
	gl.TexSubImage2D(
		gl.TEXTURE_2D, // target
		0, // level
		0, // xoffset
		0, // yoffset
		i32(image.width), // width
		i32(image.height), // height
		gl.RGBA8, // format
		gl.UNSIGNED_BYTE, // type
		data, // data
	)

	if err := gl.GetError(); err != gl.NO_ERROR {
		log.errorf("Error while setting image data: %x", err)
	}

	gl.BindTexture(gl.TEXTURE_2D, 0)
}
