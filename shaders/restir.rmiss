#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_GOOGLE_include_directive : enable

#include "ray_common.glsl"

struct RestirPayload {
    vec3 position;
    vec3 normal;
    Material material;
    bool hit;
};

layout(location = 0) rayPayloadInEXT RayPayload payload;

void main() {
    payload.hit = false;
}
