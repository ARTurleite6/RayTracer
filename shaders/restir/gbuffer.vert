#version 460

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;

layout(location = 0) out vec3 outPos;
layout(location = 1) out vec3 outNormal;

layout(binding = 0, set = 0) uniform CameraUBO {
    mat4 projection;
    mat4 view;
    mat4 inverse_view;
    mat4 inverse_projection;
} camera;

layout(push_constant) uniform Push {
    mat4 model_matrix;
    mat4 normal_matrix;
    uint material_index;
} push;

void main()
{
    vec3 flippedPos = vec3(aPos.x, -aPos.y, aPos.z);
    vec3 flippedNormal = vec3(aNormal.x, -aNormal.y, aNormal.z);
    // Transform position to world space
    vec4 worldPos = push.model_matrix * vec4(flippedPos, 1.0);
    gl_Position = camera.projection * camera.view * worldPos;

    // Transform normal to world space using normal matrix
    // Extract upper 3x3 from the normal matrix and transform the normal
    mat3 normalMat3 = mat3(push.normal_matrix);
    vec3 worldNormal = normalize(normalMat3 * flippedNormal);

    outPos = worldPos.xyz; // World space position
    outNormal = worldNormal; // World space normal
}
