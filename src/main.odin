package main

import "core:log"
import "raytracer"

main :: proc() {
	context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
	defer log.destroy_console_logger(context.logger)
	app := &raytracer.Application{}
	err := raytracer.application_init(app, 1920, 1080, "Raytracer")
	if err != nil {
		log.errorf("Application: Error launching application %v", err)
		return
	}
	_ = app
	defer raytracer.application_destroy(app^)

	raytracer.application_run(app)
}
