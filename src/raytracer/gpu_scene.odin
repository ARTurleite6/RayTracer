package raytracer

import "core:log"
import vk "vendor:vulkan"
_ :: log

GPU_Scene :: struct {
	meshes_data:                      []Mesh_GPU_Data,
	objects_buffer, materials_buffer: Buffer,

	// descriptors
	descriptor_set_layout:            vk.DescriptorSetLayout,
	descriptor_set:                   vk.DescriptorSet,
	vulkan_ctx:                       ^Vulkan_Context,
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

// Change this in the future
Mesh_GPU_Data :: struct {
	vertex_buffer, index_buffer: Buffer,
}

gpu_scene_init :: proc(scene: ^GPU_Scene, ctx: ^Vulkan_Context) {
	scene.vulkan_ctx = ctx

	bindings := [?]vk.DescriptorSetLayoutBinding {
		{
			binding = 0,
			descriptorCount = 1,
			descriptorType = .ACCELERATION_STRUCTURE_KHR,
			stageFlags = {.RAYGEN_KHR},
		},
		{
			binding = 1,
			descriptorCount = 1,
			descriptorType = .STORAGE_BUFFER,
			stageFlags = {.CLOSEST_HIT_KHR},
		},
		{
			binding = 2,
			descriptorCount = 1,
			descriptorType = .STORAGE_BUFFER,
			stageFlags = {.CLOSEST_HIT_KHR},
		},
	}

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(bindings)),
		pBindings    = raw_data(bindings[:]),
	}

	vk.CreateDescriptorSetLayout(
		vulkan_get_device_handle(scene.vulkan_ctx),
		&create_info,
		nil,
		&scene.descriptor_set_layout,
	)

	{
		alloc_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = scene.vulkan_ctx.descriptor_pool,
			descriptorSetCount = 1,
			pSetLayouts        = &scene.descriptor_set_layout,
		}

		vk.AllocateDescriptorSets(
			vulkan_get_device_handle(scene.vulkan_ctx),
			&alloc_info,
			&scene.descriptor_set,
		)
	}

}

scene_compile :: proc(gpu_scene: ^GPU_Scene, scene: Scene) {
	gpu_scene.meshes_data = make([]Mesh_GPU_Data, len(scene.meshes))
	objects_data := make([]Object_GPU_Data, len(scene.objects), context.temp_allocator)
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
	}

	buffer_init_with_staging_buffer(
		&gpu_scene.objects_buffer,
		gpu_scene.vulkan_ctx,
		raw_data(objects_data),
		size_of(Object_GPU_Data),
		len(objects_data),
		{.SHADER_DEVICE_ADDRESS, .STORAGE_BUFFER},
	)

	write_info: [1]vk.WriteDescriptorSet
	{
		buffer_info := vk.DescriptorBufferInfo {
			buffer = gpu_scene.objects_buffer.handle,
			offset = 0,
			range  = gpu_scene.objects_buffer.size,
		}
		write_info[0] = {
			sType           = .WRITE_DESCRIPTOR_SET,
			pBufferInfo     = &buffer_info,
			dstSet          = gpu_scene.descriptor_set,
			dstBinding      = 1,
			descriptorType  = .STORAGE_BUFFER,
			descriptorCount = 1,
		}
	}


	vk.UpdateDescriptorSets(
		vulkan_get_device_handle(gpu_scene.vulkan_ctx),
		u32(len(write_info)),
		raw_data(write_info[:]),
		0,
		nil,
	)
}

gpu_scene_destroy :: proc(scene: ^GPU_Scene) {
	for &mesh in scene.meshes_data {
		buffer_destroy(&mesh.vertex_buffer)
		buffer_destroy(&mesh.index_buffer)
	}
	buffer_destroy(&scene.objects_buffer)
	buffer_destroy(&scene.materials_buffer)

	vk.DestroyDescriptorSetLayout(
		vulkan_get_device_handle(scene.vulkan_ctx),
		scene.descriptor_set_layout,
		nil,
	)

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

	{
		buffer_info := vk.DescriptorBufferInfo {
			buffer = gpu_scene.materials_buffer.handle,
			offset = 0,
			range  = gpu_scene.materials_buffer.size,
		}
		write_info := vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			pBufferInfo     = &buffer_info,
			dstSet          = gpu_scene.descriptor_set,
			dstBinding      = 2,
			descriptorType  = .STORAGE_BUFFER,
			descriptorCount = 1,
		}

		vk.UpdateDescriptorSets(
			vulkan_get_device_handle(gpu_scene.vulkan_ctx),
			1,
			&write_info,
			0,
			nil,
		)
	}
}

gpu_scene_recreate_materials_buffer :: proc(gpu_scene: ^GPU_Scene, scene: Scene) {
	buffer_destroy(&gpu_scene.materials_buffer)
	gpu_scene_create_materials_buffer(gpu_scene, scene)
}

gpu_scene_update_objects_buffer :: proc(gpu_scene: ^GPU_Scene, scene: ^Scene) {
	for dirty_object in scene.dirty_objects {
		object := &scene.objects[dirty_object]
		mesh := &gpu_scene.meshes_data[object.mesh_index]

		object_data := Object_GPU_Data {
			vertex_buffer_address = buffer_get_device_address(mesh.vertex_buffer),
			index_buffer_address  = buffer_get_device_address(mesh.index_buffer),
			material_index        = u32(object.material_index),
			mesh_index            = u32(object.mesh_index),
		}

		offset := vk.DeviceSize(dirty_object * size_of(Object_GPU_Data))

		buffer_update_region(
			&gpu_scene.objects_buffer,
			&object_data,
			size_of(Object_GPU_Data),
			offset,
		)
	}

	clear(&scene.dirty_objects)
}

gpu_scene_update_materials_buffer :: proc(gpu_scene: ^GPU_Scene, scene: ^Scene) {
	for dirty_material in scene.dirty_materials {
		material := &scene.materials[dirty_material]

		material_data := Material_Data {
			albedo         = material.albedo,
			emission_color = material.emission_color,
			emission_power = material.emission_power,
			roughness      = material.roughness,
			metallic       = material.metallic,
			transmission   = material.transmission,
			ior            = material.ior,
		}

		offset := vk.DeviceSize(dirty_material * size_of(Material_Data))

		buffer_update_region(
			&gpu_scene.materials_buffer,
			&material_data,
			size_of(Material_Data),
			offset,
		)
	}

	clear(&scene.dirty_materials)
}
