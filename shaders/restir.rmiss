#version 460

#extension GL_EXT_ray_tracing : require

// Ray payload (not used in this simple example)
layout(location = 0) rayPayloadInEXT vec3 hitValue;

void main() {
    // Return red color when ray misses (background)
    hitValue = vec3(1.0, 0.0, 0.0);
}
