package main

import "core:log"
import "raytracer"

main :: proc() {
	context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
	defer log.destroy_console_logger(context.logger)
	app, err := raytracer.make_application(1920, 1080, "Raytracer")
	if err != nil {
		log.errorf("Application: Error launching application %v", err)
		return
	}
	defer raytracer.delete_application(app)

	raytracer.application_run(&app)
}
