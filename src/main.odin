package main

import "core:fmt"
import "core:log"
@(require) import "core:mem"
import os "core:os/os2"
import "raytracer"

main :: proc() {
	context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
	defer log.destroy_console_logger(context.logger)
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				log.warnf("=== %v allocations not freed: ===", len(track.allocation_map))
				for _, entry in track.allocation_map {
					log.warnf("- %v bytes @ %v", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	if len(os.args) < 2 {
		fmt.eprintln("Usage: pathtracer.exe <scene_file>")
		return
	}

	fullscreen_mode := false
	if len(os.args) > 2 && (os.args[2] == "-f" || os.args[2] == "--fullscreen") {
		log.info("Creating fullscreen window")
		fullscreen_mode = true
	}

	scene_file := os.args[1]
	app, err := raytracer.application_init(
		1280,
		1020,
		"Raytracer",
		scene_file,
		window_fullscreen = fullscreen_mode,
	)
	if err != nil {
		log.errorf("Application: Error launching application %v", err)
		return
	}
	defer raytracer.application_destroy(app)

	raytracer.application_run(app)
}

