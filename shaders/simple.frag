#version 460

layout(set = 0, binding = 0) uniform sampler2D gBufferAlbedo;

layout(location = 0) in vec2 inUV;
layout(location = 0) out vec4 outColor;

void main() {
    vec3 albedo = texture(gBufferAlbedo, ivec2(inUV)).rgb;
    outColor = vec4(albedo, 1.0);
}
