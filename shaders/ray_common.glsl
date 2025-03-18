#extension GL_EXT_shader_explicit_arithmetic_types_int64 : enable

struct Material {
    vec3 albedo;
    vec3 emission_color;
    float emission_power;
};

struct RayPayload {
    vec3 color;
    Material material;
    vec3 hitPosition;
    vec3 hitNormal;
    bool hit;
};

struct ObjectData {
    uint64_t vertex_address;
    uint64_t index_address;
    uint material_index;
    uint mesh_index;
};

struct Vertex {
    vec3 pos;
    vec3 normal;
    vec3 color;
};
