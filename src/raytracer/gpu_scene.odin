package raytracer

import "base:intrinsics"
import "core:log"
import vk "vendor:vulkan"
_ :: log

GPU_Scene :: struct {
	meshes_data:                                     []Mesh_GPU_Data,
	objects_buffer, materials_buffer, lights_buffer: Buffer,

	// descriptors
	descriptor_set:                                  Descriptor_Set,
	vulkan_ctx:                                      ^Vulkan_Context,
}

Material_Data :: struct {
	albedo, emission_color:                                 Vec3,
	emission_power, roughness, metallic, transmission, ior: f32,
}

Object_GPU_Data :: struct {
	vertex_buffer_address: vk.DeviceAddress,
	index_buffer_address:  vk.DeviceAddress,
	material_index:        u32,
	mesh_index:            u32,
}

Light_GPU_Data :: struct {
	transform:     [16]f32,
	object_index:  u32,
	num_triangles: u32,
}

// Change this in the future
Mesh_GPU_Data :: struct {
	vertex_buffer, index_buffer: Buffer,
}

gpu_scene_init :: proc(
	scene: ^GPU_Scene,
	scene_descriptor_set_layout: ^Descriptor_Set_Layout,
	ctx: ^Vulkan_Context,
) {
	scene.vulkan_ctx = ctx

	scene.descriptor_set = descriptor_set_allocate(scene_descriptor_set_layout)
}

scene_compile :: proc(gpu_scene: ^GPU_Scene, scene: Scene) {
	gpu_scene.meshes_data = make([]Mesh_GPU_Data, len(scene.meshes))
	objects_data := make([]Object_GPU_Data, len(scene.objects), context.temp_allocator)
	lights_data := make([dynamic]Light_GPU_Data, context.temp_allocator)

	for mesh, i in scene.meshes {
		gpu_mesh: Mesh_GPU_Data

		buffer_init_with_staging_buffer(
			&gpu_mesh.vertex_buffer,
			gpu_scene.vulkan_ctx,
			raw_data(mesh.vertices),
			size_of(Vertex),
			len(mesh.vertices),
			{.SHADER_DEVICE_ADDRESS, .ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
		)

		buffer_init_with_staging_buffer(
			&gpu_mesh.index_buffer,
			gpu_scene.vulkan_ctx,
			raw_data(mesh.indices),
			size_of(u32),
			len(mesh.indices),
			{.SHADER_DEVICE_ADDRESS, .ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_KHR},
		)

		gpu_scene.meshes_data[i] = gpu_mesh
	}

	gpu_scene_create_materials_buffer(gpu_scene, scene)

	for object, i in scene.objects {
		gpu_object: Object_GPU_Data
		mesh := gpu_scene.meshes_data[object.mesh_index]

		gpu_object.vertex_buffer_address = buffer_get_device_address(mesh.vertex_buffer)
		gpu_object.index_buffer_address = buffer_get_device_address(mesh.index_buffer)
		gpu_object.material_index = u32(object.material_index)
		gpu_object.mesh_index = u32(object.mesh_index)

		objects_data[i] = gpu_object

		if scene.materials[object.material_index].emission_power > 0 {
			append(
				&lights_data,
				Light_GPU_Data {
					transform = intrinsics.matrix_flatten(object.transform.model_matrix),
					object_index = u32(i),
					num_triangles = u32(len(scene.meshes[object.mesh_index].indices) / 3),
				},
			)
		}
	}

	buffer_init_with_staging_buffer(
		&gpu_scene.objects_buffer,
		gpu_scene.vulkan_ctx,
		raw_data(objects_data),
		size_of(Object_GPU_Data),
		len(objects_data),
		{.SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER},
	)


	buffer_init_with_staging_buffer(
		&gpu_scene.lights_buffer,
		gpu_scene.vulkan_ctx,
		raw_data(lights_data),
		size_of(Light_GPU_Data),
		len(lights_data),
		{.SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER},
	)

	descriptor_set_update(
		&gpu_scene.descriptor_set,
		{binding = 1, write_info = buffer_descriptor_info(gpu_scene.objects_buffer)},
		{binding = 3, write_info = buffer_descriptor_info(gpu_scene.lights_buffer)},
	)
}

gpu_scene_destroy :: proc(scene: ^GPU_Scene) {
	for &mesh in scene.meshes_data {
		buffer_destroy(&mesh.vertex_buffer)
		buffer_destroy(&mesh.index_buffer)
	}
	buffer_destroy(&scene.objects_buffer)
	buffer_destroy(&scene.materials_buffer)

	delete(scene.meshes_data)
}

gpu_scene_create_materials_buffer :: proc(gpu_scene: ^GPU_Scene, scene: Scene) {
	materials_data := make([]Material_Data, len(scene.materials), context.temp_allocator)
	for material, i in scene.materials {
		materials_data[i] = {
			albedo         = material.albedo,
			emission_color = material.emission_color,
			emission_power = material.emission_power,
			roughness      = material.roughness,
			metallic       = material.metallic,
			transmission   = material.transmission,
			ior            = material.ior,
		}
	}
	buffer_init_with_staging_buffer(
		&gpu_scene.materials_buffer,
		gpu_scene.vulkan_ctx,
		raw_data(materials_data),
		size_of(Material_Data),
		len(materials_data),
		{.SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER},
	)

	descriptor_set_update(
		&gpu_scene.descriptor_set,
		{binding = 2, write_info = buffer_descriptor_info(gpu_scene.materials_buffer)},
	)
}

gpu_scene_recreate_materials_buffer :: proc(gpu_scene: ^GPU_Scene, scene: Scene) {
	buffer_destroy(&gpu_scene.materials_buffer)
	gpu_scene_create_materials_buffer(gpu_scene, scene)
}

gpu_scene_update_object :: proc(gpu_scene: ^GPU_Scene, scene: ^Scene, object_index: int) {
	object := &scene.objects[object_index]
	mesh := &gpu_scene.meshes_data[object.mesh_index]

	object_data := Object_GPU_Data {
		vertex_buffer_address = buffer_get_device_address(mesh.vertex_buffer),
		index_buffer_address  = buffer_get_device_address(mesh.index_buffer),
		material_index        = u32(object.material_index),
		mesh_index            = u32(object.mesh_index),
	}

	offset := vk.DeviceSize(object_index * size_of(Object_GPU_Data))

	buffer_update_region(&gpu_scene.objects_buffer, &object_data, size_of(Object_GPU_Data), offset)
}

gpu_scene_update_material :: proc(gpu_scene: ^GPU_Scene, scene: ^Scene, material_index: int) {
	material := &scene.materials[material_index]

	material_data := Material_Data {
		albedo         = material.albedo,
		emission_color = material.emission_color,
		emission_power = material.emission_power,
		roughness      = material.roughness,
		metallic       = material.metallic,
		transmission   = material.transmission,
		ior            = material.ior,
	}

	offset := vk.DeviceSize(material_index * size_of(Material_Data))

	buffer_update_region(
		&gpu_scene.materials_buffer,
		&material_data,
		size_of(Material_Data),
		offset,
	)
}
