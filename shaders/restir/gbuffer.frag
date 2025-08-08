#version 460

#extension GL_EXT_scalar_block_layout : enable

#include "../ray_common.glsl"

layout(location = 0) in vec3 inPos;
layout(location = 1) in vec3 inNormal;

layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormal;
layout(location = 2) out vec4 outPos;
layout(location = 3) out vec4 outEmission;
layout(location = 4) out vec3 outMaterialProps;

layout(set = 0, binding = 1, scalar) buffer readonly Materials {
    Material materials[];
};

layout(push_constant) uniform Push {
    mat4 model_matrix;
    mat4 normal_matrix;
    uint material_index;
} push;

void main()
{
    Material material = materials[push.material_index];
    // Show object-space normals directly from vertex buffer
    // This should show smooth color gradients on a sphere
    vec3 normalColor = normalize(inNormal) * 0.5 + 0.5;

    outAlbedo = vec4(material.albedo, 1.0);
    outNormal = vec4(normalize(inNormal), material.metallic);
    outPos = vec4(inPos, material.roughness);
    bool isEmissive = material.emission_power > 0.0;
    outEmission = vec4(material.emission_power * material.emission_color, isEmissive);
    outMaterialProps = vec3(material.roughness, material.metallic, isEmissive);
}
