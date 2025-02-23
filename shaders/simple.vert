#version 450

layout(push_constant) uniform Push {
    mat4 model_matrix;
} push;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inColor;

layout(location = 0) out vec3 fragColor;

void main() {
    gl_Position = push.model_matrix * vec4(inPosition, 1.0);
    fragColor = inColor;
}
