package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os/os2"
import "raytracer"
_ :: mem
_ :: fmt

main :: proc() {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
		defer log.destroy_console_logger(context.logger)

		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	scene_path: Maybe(string)
	if len(os2.args) > 1 {
		scene_path = os2.args[1]
	}

	app, err := raytracer.application_init(1280, 1020, "Raytracer", scene_path = scene_path)
	if err != nil {
		log.errorf("Application: Error launching application %v", err)
		return
	}
	_ = app
	defer raytracer.application_destroy(app)

	raytracer.application_run(app)
}
