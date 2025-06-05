#version 460

layout(binding = 0, set = 0) uniform CameraProperties {
    mat4 proj;
    mat4 view;
    mat4 inverse_view;
    mat4 inverse_proj;
} cam;

layout(location = 0) in vec3 fragColor;

layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(fragColor, 1.0);
}
