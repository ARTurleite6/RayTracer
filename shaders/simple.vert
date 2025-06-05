#version 460

layout(binding = 0, set = 1) uniform CameraProperties {
    mat4 proj;
    mat4 view;
    mat4 inverse_view;
    mat4 inverse_proj;
} cam;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inColor;

layout(location = 0) out vec3 fragColor;

void main() {
    gl_Position = vec4(inPosition, 1.0);
    fragColor = inColor;
}
