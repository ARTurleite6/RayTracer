#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_GOOGLE_include_directive : enable

#include "ray_common.glsl"

struct RestirPayload {
    vec3 position;
    vec3 normal;
    Material material;
    bool hit;
};

hitAttributeEXT vec2 attribs;

layout(location = 0) rayPayloadInEXT RestirPayload payload;

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

void main() {
    ObjectData object = objects_data.objects[gl_InstanceCustomIndexEXT];
    payload.hit = true;
    payload.material = materials_data.materials[object.material_index];

    Vertices vert = Vertices(object.vertex_address);
    Indices indices = Indices(object.index_address);

    ivec3 ind = indices.indices[gl_PrimitiveID];

    Vertex v0 = vert.v[ind.x];
    Vertex v1 = vert.v[ind.y];
    Vertex v2 = vert.v[ind.z];

    const vec3 barycentrics = vec3(1.0 - attribs.x - attribs.y, attribs.x, attribs.y);
    const vec3 pos = v0.pos * barycentrics.x + v1.pos * barycentrics.y + v2.pos * barycentrics.z;
    vec3 worldPos = vec3(gl_ObjectToWorldEXT * vec4(pos, 1.0));

    const vec3 norm = normalize(v0.normal * barycentrics.x + v1.normal * barycentrics.y + v2.normal * barycentrics.z);
    vec3 worldNrm = normalize(transpose(inverse(mat3(gl_ObjectToWorldEXT))) * norm);

    payload.position = worldPos;
    payload.normal = worldNrm;
}
