#version 460

#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : enable

#include "ray_common.glsl"

layout(location = 1) rayPayloadEXT ShadowPayload payload;

void main() {
  payload.hitLight = true;
  payload.lightIndex = gl_InstanceCustomIndexEXT;
}
