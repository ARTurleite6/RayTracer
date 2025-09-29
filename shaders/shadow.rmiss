#version 460

#extension GL_EXT_ray_tracing : enable
#extension GL_GOOGLE_include_directive : enable

#include "ray_common.glsl"

layout(location = 1) rayPayloadInEXT ShadowPayload payload;

void main() {
  payload.occluded = false;
  payload.hitLight = false;
  payload.lightIndex = 0xFFu;
}
