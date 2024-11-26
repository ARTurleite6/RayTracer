package raytracer

@(require, extra_linker_flags = "-rpath /usr/local/lib")
foreign import __ "system:System.framework"

import "core:mem"
import "core:slice"
import "vendor:glfw"
import vk "vendor:vulkan"

Context_Error :: union #shared_nil {
	vk.Result,
	Shader_Error,
}

Context :: struct {
	instance:        Instance,
	physical_device: PhysicalDevice,
	device:          Device,
	present_queue:   vk.Queue,
	graphics_queue:  vk.Queue,
	surface:         vk.SurfaceKHR,
	swapchain:       Swapchain,
	pipeline:        Pipeline,
	render_pass:     vk.RenderPass,
	shaders:         []Shader,
	command_pool:    Command_Pool,
	debugger:        Debugger,
}

@(require_results)
context_init :: proc(
	ctx: ^Context,
	window: Window,
	allocator: mem.Allocator,
	temp_allocator: mem.Allocator,
) -> (
	result: Context_Error,
) {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
	extensions := required_extensions(temp_allocator)
	debug_info: ^vk.DebugUtilsMessengerCreateInfoEXT
	when ODIN_DEBUG {
		debug_info_value: vk.DebugUtilsMessengerCreateInfoEXT
		debugger_get_info(&debug_info_value)
		debug_info = &debug_info_value
	}

	if result = instance_init(&ctx.instance, "Raytracing", extensions, debug_info);
	   result != vk.Result.SUCCESS {
		return
	}
	vk.load_proc_addresses(ctx.instance)
	if debug_info != nil {
		debugger_init(&ctx.debugger, ctx.instance, debug_info)
	}

	if ctx.surface, result = window_create_surface(window, ctx.instance);
	   result != vk.Result.SUCCESS {
		return
	}

	physical_device_init(&ctx.physical_device, ctx.instance, ctx.surface, temp_allocator)

	queues := find_queue_families(ctx.physical_device, ctx.surface, temp_allocator)
	if result = device_init(&ctx.device, ctx.physical_device, ctx.surface, queues, temp_allocator);
	   result != vk.Result.SUCCESS {
		return
	}
	vk.load_proc_addresses_device(ctx.device)

	vk.GetDeviceQueue(ctx.device, queues.graphics.?, 0, &ctx.graphics_queue)
	vk.GetDeviceQueue(ctx.device, queues.present.?, 0, &ctx.present_queue)

	// Go to creating the Swapchain
	swapchain_init(
		&ctx.swapchain,
		ctx.device,
		ctx.physical_device,
		ctx.surface,
		window,
		queues,
		allocator,
		temp_allocator,
	)

	{ 	// create shaders
		// TODO: for now the shaders will be only two and will be hardcoded
		ctx.shaders = make([]Shader, 2, allocator)

		shader_init(
			&ctx.shaders[0],
			ctx.device,
			{.VERTEX},
			"main",
			"shaders/vert.spv",
			temp_allocator,
		) or_return

		shader_init(
			&ctx.shaders[1],
			ctx.device,
			{.FRAGMENT},
			"main",
			"shaders/frag.spv",
			temp_allocator,
		) or_return
	}

	context_render_pass_init(&ctx.render_pass, ctx.device, ctx.swapchain)

	pipeline_init(
		&ctx.pipeline,
		ctx.device,
		ctx.swapchain,
		ctx.render_pass,
		ctx.shaders,
		temp_allocator,
	)

	swapchain_init_framebuffers(&ctx.swapchain, ctx.device, ctx.render_pass, allocator)
	if result := command_pool_init(&ctx.command_pool, ctx.device, queues.graphics.?);
	   result != .SUCCESS {
		return result
	}

	return
}

context_destroy :: proc(ctx: ^Context) {
	command_pool_destroy(&ctx.command_pool, ctx.device)
	pipeline_destroy(ctx.pipeline, ctx.device)
	vk.DestroyRenderPass(ctx.device, ctx.render_pass, nil)

	for shader in ctx.shaders {
		shader_destroy(shader, ctx.device)
	}
	delete(ctx.shaders)

	swapchain_destroy(ctx.swapchain, ctx.device)
	device_destroy(ctx.device)
	vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)
	debugger_destroy(ctx.debugger, ctx.instance)
	instance_destroy(ctx.instance)
}

context_render_pass_init :: proc(
	render_pass: ^vk.RenderPass,
	device: Device,
	swapchain: Swapchain,
) -> vk.Result {
	color_attachment := vk.AttachmentDescription {
		format         = swapchain.format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}
	color_attachment_ref := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	subpass := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_attachment_ref,
	}

	dependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}

	create_info := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attachment,
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}

	if result := vk.CreateRenderPass(device, &create_info, nil, render_pass); result != .SUCCESS {
		return result
	}
	return .SUCCESS
}

required_extensions :: proc(temp_allocator: mem.Allocator) -> []cstring {
	extensions := slice.to_dynamic(glfw.GetRequiredInstanceExtensions(), temp_allocator)

	when ODIN_OS == .Darwin {
		append(&extensions, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}

	when ODIN_DEBUG {
		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}

	return extensions[:]
}
