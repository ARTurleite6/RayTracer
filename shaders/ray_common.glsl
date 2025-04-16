#extension GL_EXT_shader_explicit_arithmetic_types_int64 : enable

struct Material {
    vec3 albedo;
    vec3 emission_color;
    float emission_power;
    float roughness;
    float metallic;
    float transmission;
    float ior;
};

struct RayPayload {
    vec3 color;
    vec3 throughput;
    vec3 hitPosition;
    vec3 nextDirection;
    uint seed;
    bool hit;
    bool firstBounce;
    bool isSpecular;
};

struct ObjectData {
    uint64_t vertex_address;
    uint64_t index_address;
    uint material_index;
    uint mesh_index;
};

struct LightData {
    mat4 transform;
    uint object_index, num_triangles;
};

struct Vertex {
    vec3 pos;
    vec3 normal;
    vec3 color;
};
