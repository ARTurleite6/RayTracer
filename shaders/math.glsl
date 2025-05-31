#define M_PI 3.14159265359

float powerHeuristic(float pdfA, float pdfB) {
    float a2 = pdfA * pdfA;
    float b2 = pdfB * pdfB;
    return a2 / (a2 + b2);
}

mat3 createBasis(vec3 normal) {
    // Find a perpendicular vector to the normal
    vec3 nt = normalize(abs(normal.x) > 0.1 ? vec3(0, 1, 0) : vec3(1, 0, 0));
    vec3 tangent = normalize(cross(nt, normal));
    vec3 bitangent = cross(normal, tangent);

    return mat3(tangent, bitangent, normal);
}

// Transform a world-space direction to local space where normal is (0,0,1)
vec3 worldToLocal(vec3 v, mat3 basis) {
    return vec3(
        dot(v, basis[0]),
        dot(v, basis[1]),
        dot(v, basis[2])
    );
}

// Transform a local-space direction to world space
vec3 localToWorld(vec3 v, mat3 basis) {
    return basis[0] * v.x + basis[1] * v.y + basis[2] * v.z;
}

float cosTheta(vec3 w) {
    return w.z;
}

float absCosTheta(vec3 w) {
    return abs(w.z);
}

float max3(vec3 v) {
    return max(v.x, max(v.y, v.z));
}
