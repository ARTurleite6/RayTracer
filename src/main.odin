package main

import "core:fmt"
import "raytracer"

main :: proc() {
	app: raytracer.Application
	if err := raytracer.application_init(
		&app,
		800,
		600,
		"Raytracer",
		context.allocator,
		context.temp_allocator,
	); err != nil {
		fmt.eprintfln("Error while initialing Application %v", err)
		return
	}
	defer raytracer.application_destroy(&app)

	raytracer.application_run(&app)
}
