#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_GOOGLE_include_directive : enable

#include "ray_common.glsl"
#include "random.glsl"

hitAttributeEXT vec2 attribs;

layout(location = 0) rayPayloadInEXT RayPayload payload;
layout(location = 1) rayPayloadEXT bool isShadowed;

layout(binding = 0, set = 1) uniform accelerationStructureEXT topLevelAS;
layout(buffer_reference, scalar) buffer Vertices {
    Vertex v[];
};

layout(buffer_reference, scalar) buffer Indices {
    ivec3 indices[];
};

layout(set = 1, binding = 1, scalar) buffer ObjectsData {
    ObjectData objects[];
} objects_data;

layout(set = 1, binding = 2, scalar) buffer MaterialsBuffer {
    Material materials[];
} materials_data;

layout(push_constant) uniform Push {
    vec3 clear_color;
    uint frame_number;
} push;

#define M_PI 3.14159265359

struct SurfaceInteractionResult {
    vec3 brdf;
    float pdf;
    vec3 scatteredDirection;
};

vec3 generateCosineWeightedDirection(vec2 random) {
    float phi = 2.0 * M_PI * random.x;
    float cosTheta = sqrt(random.y);
    float sinTheta = sqrt(1 - random.y);

    float x = cos(phi) * sinTheta;
    float y = sin(phi) * sinTheta;
    float z = cosTheta;

    return vec3(x, y, z);
}

vec3 generateLambertianRay(vec3 normal, vec2 random) {
    vec3 nt = normalize(abs(normal.x) > 0.1f ? vec3(0, 1, 0) : vec3(1, 0, 0));
    vec3 tangent = normalize(cross(nt, normal));
    vec3 bitangent = cross(normal, tangent);

    vec3 localDir = generateCosineWeightedDirection(random);

    return normalize(
        localDir.x * tangent + localDir.y * bitangent + localDir.z * normal
    );
}

float lambertianPDF(vec3 normal, vec3 direction) {
    float cosTheta = max(0.0, dot(normal, direction));

    return cosTheta / M_PI;
}

SurfaceInteractionResult surfaceInteraction(vec3 normal, Material material, vec2 random) {
    SurfaceInteractionResult result;
    result.scatteredDirection = generateLambertianRay(normal, random);
    result.brdf = material.albedo / M_PI;
    result.pdf = lambertianPDF(normal, result.scatteredDirection);

    return result;
}

vec3 sampleDirectLighting(vec3 hitPos, vec3 normal, uint seed) {
    vec3 directIllumination = vec3(0.0);

    for (int i = 0; i < objects_data.objects.length(); i++) {
        ObjectData lightObject = objects_data.objects[i];
        Material lightMaterial = materials_data.materials[lightObject.material_index];

        if (lightMaterial.emission_power <= 0.0) continue;

        Vertices lightVerts = Vertices(lightObject.vertex_address);
        Indices lightIndices = Indices(lightObject.index_address);
    }

    return directIllumination;
}

void main() {
    uint seed = payload.seed;
    ObjectData object = objects_data.objects[gl_InstanceCustomIndexEXT];
    Material mat = materials_data.materials[object.material_index];
    //
    Vertices vert = Vertices(object.vertex_address);
    Indices indices = Indices(object.index_address);

    ivec3 ind = indices.indices[gl_PrimitiveID];

    Vertex v0 = vert.v[ind.x];
    Vertex v1 = vert.v[ind.y];
    Vertex v2 = vert.v[ind.z];

    const vec3 barycentrics = vec3(1.0 - attribs.x - attribs.y, attribs.x, attribs.y);
    const vec3 pos = v0.pos * barycentrics.x + v1.pos * barycentrics.y + v2.pos * barycentrics.z;
    vec3 worldPos = vec3(gl_ObjectToWorldEXT * vec4(pos, 1.0));

    const vec3 norm = v0.normal * barycentrics.x + v1.normal * barycentrics.y + v2.normal * barycentrics.z;
    const vec3 worldNrm = normalize(vec3(norm * gl_WorldToObjectEXT)); // Transforming the normal to world space

    { // direct illumination
        isShadowed = false;
    }

    vec2 random = vec2(
            rnd(seed),
            rnd(seed)
        );

    SurfaceInteractionResult result = surfaceInteraction(worldNrm, mat, random);

    vec3 brdf = (payload.color / M_PI);
    float pdf = lambertianPDF(worldNrm, result.scatteredDirection);

    float cosTheta = max(0.0, dot(worldNrm, result.scatteredDirection));
    payload.throughput *= result.brdf * cosTheta / result.pdf;

    payload.color += mat.emission_color * mat.emission_power;
    payload.hitPosition = worldPos;
    payload.nextDirection = result.scatteredDirection;
    payload.hit = true;
}
