package raytracer

Raytracing_Stage :: struct {
	using base: Render_Stage,
}

raytracing_init :: proc(stage: ^Raytracing_Stage, name: string) {
	render_stage_init(stage, name, stage)
}

create_rt_pipeline :: proc() {

}
