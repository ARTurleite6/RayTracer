package main

import "core:log"
@(require) import "core:mem"
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

	// if err != nil {
	// 	fmt.printfln("Error loading scene: %v", err)
	// }
	// _ = scene
	//
	// scene_path: Maybe(string)
	// if len(os2.args) > 1 {
	// 	scene_path = os2.args[1]
	// }

	app, err := raytracer.application_init(1280, 1020, "Raytracer")
	if err != nil {
		log.errorf("Application: Error launching application %v", err)
		return
	}
	defer raytracer.application_destroy(app)

	raytracer.application_run(app)
}
