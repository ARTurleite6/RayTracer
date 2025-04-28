#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_GOOGLE_include_directive : enable

#include "ray_common.glsl"
#include "random.glsl"
#include "math.glsl"

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

layout(set = 1, binding = 3, scalar) buffer LightsBuffer {
    LightData lights[];
} lights_data;

layout(push_constant) uniform Push {
    vec3 clear_color;
    uint frame_number;
} push;

struct SurfaceInteractionResult {
    vec3 brdf;
    float pdf;
    vec3 scatteredDirection;
    bool isSpecular;
    float diffusePdf;
    float specularPdf;
};

float D_GGX(float NoH, float roughness) {
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    float denom = NoH * NoH * (alpha2 - 1.0) + 1.0;
    return alpha2 / (M_PI * denom * denom);
}

// GGX Smith geometric shadowing function
float G_Smith(float NoV, float NoL, float roughness) {
    float alpha = roughness * roughness;
    float k = alpha * 0.5;
    float G1V = NoV / (NoV * (1.0 - k) + k);
    float G1L = NoL / (NoL * (1.0 - k) + k);
    return G1V * G1L;
}

// Schlick Fresnel approximation
vec3 F_Schlick(vec3 F0, float VoH) {
    return F0 + (1.0 - F0) * pow(1.0 - VoH, 5.0);
}

vec3 generateCosineWeightedDirection(vec2 random) {
    float phi = 2.0 * M_PI * random.x;
    float cosTheta = sqrt(random.y);
    float sinTheta = sqrt(1 - random.y);

    float x = cos(phi) * sinTheta;
    float y = sin(phi) * sinTheta;
    float z = cosTheta;

    return vec3(x, y, z);
}

vec3 microfacetF(vec3 wo, vec3 wi, vec3 h, Material material) {
    float NoL = cosTheta(wi);
    float NoV = cosTheta(wo);
    float NoH = cosTheta(h);
    float VoH = dot(wo, h);

    // D term (normal distribution function)
    float D = D_GGX(NoH, material.roughness);

    // G term (geometric shadowing)
    float G = G_Smith(NoV, NoL, material.roughness);

    vec3 F0 = mix(vec3(0.04), material.albedo, material.metallic);
    // F term (Fresnel)
    vec3 F = F_Schlick(F0, VoH);

    // The Cook-Torrance microfacet BRDF
    vec3 specular = D * G * F / (4.0 * NoV * NoL);

    return specular;
}

float microfacetPDF(vec3 wo, vec3 h, float roughness) {
    float NoH = cosTheta(h);
    float VoH = dot(wo, h);

    float D = D_GGX(NoH, roughness);

    return D * NoH / (4.0 * VoH);
}

vec3 sampleGGX(vec2 random, float roughness, vec3 normal) {
    float a = roughness * roughness;

    float phi = 2.0 * M_PI * random.x;

    float cosTheta = sqrt((1.0 - random.y) / (1.0 + (a * a - 1.0) * random.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    // Convert to Cartesian coordinates in local space where normal is (0,0,1)
    vec3 localH = vec3(
            sinTheta * cos(phi),
            sinTheta * sin(phi),
            cosTheta
        );
    return localH;
}

vec3 generateLambertianRay(vec3 normal, vec2 random) {
    mat3 basis = createBasis(normal);

    vec3 localDir = generateCosineWeightedDirection(random);

    return localToWorld(localDir, basis);
}

SurfaceInteractionResult surfaceInteraction(vec3 normal, Material material, vec2 random, vec3 incomingRayDir) {
    SurfaceInteractionResult result;

    mat3 basis = createBasis(normal);
    vec3 woLocal = worldToLocal(-incomingRayDir, basis);

    vec3 F0 = mix(vec3(0.04), material.albedo, material.metallic);

    float specularProbability = max3(F0);
    if (material.metallic > 0.0) {
        specularProbability = mix(specularProbability, 1.0, material.metallic * 0.5);
    }

    if (rnd(payload.seed) < specularProbability) {
        vec3 hLocal = sampleGGX(random, material.roughness, normal);

        vec3 wiLocal = reflect(-woLocal, hLocal);

        if (cosTheta(wiLocal) <= 0.0) {
            vec3 diffuseLocal = generateCosineWeightedDirection(random);
            float diffusePdf = cosTheta(diffuseLocal) / M_PI;
            float specularPdf = 0;
            return SurfaceInteractionResult(
                material.albedo / M_PI,
                diffusePdf,
                localToWorld(diffuseLocal, basis),
                false,
                diffusePdf,
                specularPdf
            );
        } else {
            float specularPdf = microfacetPDF(woLocal, hLocal, material.roughness);
            float diffusePdf = max(cosTheta(wiLocal), 0.0) / M_PI;

            return SurfaceInteractionResult(
                microfacetF(woLocal, wiLocal, hLocal, material),
                specularPdf,
                localToWorld(wiLocal, basis),
                true,
                diffusePdf,
                specularPdf
            );
        }
    } else {
        // Diffuse sampling
        vec3 diffuseLocal = generateCosineWeightedDirection(random);

        // For non-metals only, the diffuse component is weighted by (1 - metallic)
        float nonMetalWeight = 1.0 - material.metallic;

        vec3 hLocal = normalize(woLocal + diffuseLocal);
        float diffusePdf = cosTheta(diffuseLocal) / M_PI;
        float specularPdf = cosTheta(diffuseLocal) > 0.0 ? microfacetPDF(woLocal, hLocal, material.roughness) : 0.0;

        return SurfaceInteractionResult(
            material.albedo * nonMetalWeight / M_PI, diffusePdf,
            localToWorld(diffuseLocal, basis),
            false,
            diffusePdf,
            specularPdf
        );
    }

    return result;
}

vec3 sampleDirectLighting(vec3 hitPos, vec3 normal, Material material, vec3 viewDir, uint seed) {
    vec3 directIllumination = vec3(0.0);

    const float ORIGIN_OFFSET = 0.001;
    vec3 offsetHitPos = hitPos + normal * ORIGIN_OFFSET;

    mat3 basis = createBasis(normal);
    vec3 woLocal = worldToLocal(-viewDir, basis);

    vec3 F0 = mix(vec3(0.04), material.albedo, material.metallic);

    for (int i = 0; i < lights_data.lights.length(); i++) {
        LightData light = lights_data.lights[i];
        ObjectData lightObject = objects_data.objects[light.object_index];
        Material lightMaterial = materials_data.materials[lightObject.material_index];

        // Access vertex and index buffers
        Vertices lightVerts = Vertices(lightObject.vertex_address);
        Indices lightIndices = Indices(lightObject.index_address);

        // Select a random triangle on the light
        uint num_triangles = light.num_triangles;
        uint triangleIdx = min(int(rnd(seed) * num_triangles), num_triangles - 1);
        ivec3 ind = lightIndices.indices[triangleIdx];

        // Get vertices of the selected triangle
        Vertex v0 = lightVerts.v[ind.x];
        Vertex v1 = lightVerts.v[ind.y];
        Vertex v2 = lightVerts.v[ind.z];

        // Sample point on triangle with uniform area sampling
        float r1 = rnd(seed);
        float r2 = rnd(seed);
        float sqrtR1 = sqrt(r1);

        // Barycentric coordinates
        float u = 1.0 - sqrtR1;
        float v = sqrtR1 * (1.0 - r2);
        float w = sqrtR1 * r2;

        // Compute position on the light source (in local space)
        vec3 localLightPos = u * v0.pos + v * v1.pos + w * v2.pos;

        // Transform to world space using the light object's transform matrix
        vec3 lightPos = vec3(light.transform * vec4(localLightPos, 1.0));

        // Also get the normal at this point for area light calculation
        vec3 localLightNormal = normalize(u * v0.normal + v * v1.normal + w * v2.normal);

        // TODO: Transform normal to world space (we use transpose of inverse for normals)
        mat3 normalMatrix = transpose(inverse(mat3(light.transform)));
        vec3 worldLightNormal = normalize(normalMatrix * localLightNormal);

        // Calculate light direction and distance
        vec3 toLight = lightPos - hitPos;
        float lightDistSq = dot(toLight, toLight);
        float lightDist = sqrt(lightDistSq);
        vec3 lightDir = toLight / lightDist; // Normalized direction

        // Check if light direction is in the hemisphere of the surface normal
        float NdotL = dot(normal, lightDir);
        if (NdotL <= 0.0) continue; // Light is behind the surface

        // Check if surface is visible from the light's perspective
        float LdotN = max(dot(-lightDir, worldLightNormal), 0.0);
        if (LdotN <= 0.001) continue; // Surface is behind the light

        // Cast shadow ray to check visibility
        isShadowed = true;
        const float tMin = 0.001;
        const float tMax = lightDist * 0.999;

        traceRayEXT(
            topLevelAS,
            gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT | gl_RayFlagsSkipClosestHitShaderEXT,
            0xFF,
            0,
            0,
            1,
            offsetHitPos,
            tMin,
            lightDir,
            tMax,
            1 // Payload location
        );

        if (!isShadowed) {
            vec3 wiLocal = worldToLocal(lightDir, basis);

            if (cosTheta(wiLocal) <= 0) continue;

            vec3 hLocal = normalize(woLocal + wiLocal);
            float nonMetalWeight = 1.0 - material.metallic;

            vec3 specular = microfacetF(woLocal, wiLocal, hLocal, material);

            vec3 diffuse = material.albedo * nonMetalWeight / M_PI;

            vec3 brdf = diffuse + specular;

            float attenuation = 1.0;
            float NdotL = cosTheta(wiLocal);
            float LdotN = max(dot(-lightDir, worldLightNormal), 0.0);

            vec3 emission = lightMaterial.emission_color * lightMaterial.emission_power;
            directIllumination += emission * brdf * NdotL * LdotN * attenuation;
        }
    }

    return directIllumination;
}

float evaluatePDF(vec3 wo, vec3 wi, Material material, mat3 basis) {
    vec3 woLocal = worldToLocal(wo, basis);
    vec3 wiLocal = worldToLocal(wi, basis);

    if (cosTheta(wiLocal) <= 0.0)
        return 0.0;

    // Calculate the half-vector for specular PDF
    vec3 hLocal = normalize(woLocal + wiLocal);

    // Calculate specular PDF
    float specularPdf = microfacetPDF(woLocal, hLocal, material.roughness);

    // Calculate diffuse PDF
    float diffusePdf = cosTheta(wiLocal) / M_PI;

    // Calculate probability of selecting specular or diffuse
    vec3 F0 = mix(vec3(0.04), material.albedo, material.metallic);
    float specularProbability = max3(F0);
    if (material.metallic > 0.0) {
        specularProbability = mix(specularProbability, 1.0, material.metallic * 0.5);
    }

    // Combined PDF based on the selection probability
    return specularProbability * specularPdf + (1.0 - specularProbability) * diffusePdf;
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

    const vec3 norm = normalize(v0.normal * barycentrics.x + v1.normal * barycentrics.y + v2.normal * barycentrics.z);
    const vec3 worldNrm = normalize(transpose(inverse(mat3(gl_ObjectToWorldEXT))) * norm);

    vec3 incomingRayDir = gl_WorldRayDirectionEXT;
    bool isEmissive = (mat.emission_power > 0.0);

    if (isEmissive) {
        // For emissive surfaces, we only add emission on the first bounce
        // This prevents double-counting when directly sampling lights
        if (payload.firstBounce || payload.isSpecular) {
            // Add emission directly to the final color
            payload.color += payload.throughput * mat.emission_color * mat.emission_power;
        }

        // For emissive surfaces, we typically terminate the path or make it
        // behave like a diffuse surface with very low intensity reflection
        vec2 random = vec2(rnd(seed), rnd(seed));
        payload.nextDirection = generateLambertianRay(worldNrm, random);

        // Optional: you might want to heavily attenuate throughput for emissive surfaces
        // Since they mainly emit rather than reflect
        payload.throughput *= mat.albedo * 0.1; // Low reflection for emissive surfaces
    } else {
        // For non-emissive surfaces, continue with your regular BRDF calculations

        // Sample direct lighting for non-specular components
        vec3 directLight = sampleDirectLighting(worldPos, worldNrm, mat, incomingRayDir, seed);

        payload.color += payload.throughput * directLight;

        vec2 random = vec2(rnd(seed), rnd(seed));

        // TODO: change this to convert incomingRayDir to local space and then use this on the other functions
        // Sample the BRDF to get the next ray direction
        SurfaceInteractionResult result = surfaceInteraction(worldNrm, mat, random, incomingRayDir);

        // Apply the BRDF
        vec3 L = result.scatteredDirection;
        float NoL = max(dot(worldNrm, L), 0.001);

        float misPdf = evaluatePDF(-incomingRayDir, L, mat, createBasis(worldNrm));
        float weight = 1.0;

        if (result.diffusePdf > 0 || result.specularPdf > 0) {
            float samplePdf = result.pdf;

            if (!result.isSpecular) {
                weight = powerHeuristic(samplePdf, misPdf);
            }
        }

        payload.throughput *= result.brdf * NoL * weight / result.pdf;
        payload.nextDirection = L;
        payload.isSpecular = result.isSpecular;
    }

    payload.firstBounce = false;
    payload.hitPosition = worldPos;
    payload.hit = true;
}
