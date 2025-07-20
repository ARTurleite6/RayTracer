#version 460

layout(set = 0, binding = 0, rgba8) uniform readonly image2D gBufferAlbedo;

layout(location = 0) in vec2 inUV;
layout(location = 0) out vec4 outColor;

void main() {
    ivec2 imageSize = imageSize(gBufferAlbedo);
    ivec2 pixelCoord = ivec2(inUV * imageSize);

    vec3 albedo = imageLoad(gBufferAlbedo, pixelCoord).rgb;
    outColor = vec4(albedo.rgb, 1.0);
}
