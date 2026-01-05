#version 460
#extension GL_EXT_ray_tracing : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_ray_query : require

#extension GL_GOOGLE_include_directive : enable

#define USE_DIRECT_LIGHTING 1
#define USE_LIGHT_SAMPLING_ONLY 0
#define USE_MIS 1

const int MAXLIGHTS = 256;

#include "ray_common.glsl"
#include "random.glsl"
#include "math.glsl"

hitAttributeEXT vec2 attribs;

layout(location = 0) rayPayloadInEXT RayPayload payload;

layout(binding = 0, set = 0) uniform accelerationStructureEXT topLevelAS;

layout(buffer_reference, scalar) buffer Vertices {
    Vertex v[];
};

layout(buffer_reference, scalar) buffer Indices {
    ivec3 indices[];
};

layout(set = 0, binding = 1, scalar) buffer ObjectsData {
    ObjectData objects[];
} objects_data;

layout(set = 0, binding = 2, scalar) buffer MaterialsBuffer {
    Material materials[];
} materials_data;

layout(set = 0, binding = 3, scalar) buffer LightsBuffer {
    LightData lights[];
} lights_data;

struct LightSample {
    vec3 position;
    vec3 normal;
    vec3 emission;
    float pdf;
    float distance;
    vec3 direction;
    uint instance_mask;
    bool valid;
};

struct BRDFEval {
    vec3 diffuse; // Diffuse component
    vec3 specular; // Specular component
    float diffusePdf;
    float specularPdf;
};

const float EPS_PDF = 1e-6;
const float EPS_COS = 1e-4;
const float EPS_VOH = 1e-4;
const float MIN_ROUGHNESS = 0.02; // tweak per scene

// Get selection probability for specular vs diffuse sampling
float getSpecularProbability(Material material) {
    vec3 F0 = mix(vec3(0.04), material.albedo, material.metallic);
    float baseProb = max3(F0);

    float roughnessInfluence = smoothstep(0.0, 1.0, material.roughness * 0.7);
    return mix(baseProb, baseProb * 0.5, roughnessInfluence);
}

float D_GGX(float NoH, float roughness) {
    float a = max(roughness, MIN_ROUGHNESS);
    float a2 = a * a;
    float nh = clamp(NoH, 0.0, 1.0);
    float denom = nh * nh * (a2 - 1.0) + 1.0;
    return a2 / (M_PI * denom * denom);
}

float G_Smith(float NoV, float NoL, float roughness) {
    float a = max(roughness, MIN_ROUGHNESS);
    float k = a * 0.5;
    float nv = clamp(NoV, EPS_COS, 1.0);
    float nl = clamp(NoL, EPS_COS, 1.0);
    float G1V = nv / (nv * (1.0 - k) + k);
    float G1L = nl / (nl * (1.0 - k) + k);
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

// Utility functions
float luminance(vec3 color) {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

// Replace evaluateBRDFComponents with this faster version
BRDFEval evaluateBRDFComponents(vec3 wo, vec3 wi, Material material) {
    BRDFEval result;

    // Calculate necessary vectors and dot products
    float NoL = cosTheta(wi);
    float NoV = cosTheta(wo);

    if (NoL <= 0.0 || NoV <= 0.0) {
        // Below horizon - no contribution
        result.diffuse = vec3(0.0);
        result.specular = vec3(0.0);
        result.diffusePdf = 0.0;
        result.specularPdf = 0.0;
        return result;
    }

    // Calculate half-vector
    vec3 h = normalize(wo + wi);
    float NoH = cosTheta(h);
    float VoH = dot(wo, h);

    // Fresnel term
    vec3 F0 = mix(vec3(0.04), material.albedo, material.metallic);
    vec3 F = F_Schlick(F0, VoH);

    // Calculate diffuse term (Lambert)
    float nonMetalWeight = 1.0 - material.metallic;
    vec3 diffuseAlbedo = material.albedo * nonMetalWeight;
    result.diffuse = diffuseAlbedo * (vec3(1.0) - F) / M_PI;
    result.diffusePdf = NoL / M_PI;

    // Calculate specular microfacet term
    // D term (normal distribution function)
    float D = D_GGX(NoH, material.roughness);

    // G term (geometric shadowing)
    float G = G_Smith(NoV, NoL, material.roughness);

    result.specular = D * G * F / (4.0 * NoV * NoL);
    result.specularPdf = D * NoH / (4.0 * VoH);

    return result;
}

// Evaluate full BRDF (diffuse + specular)
vec3 evaluateFullBRDF(vec3 wo, vec3 wi, Material material) {
    BRDFEval eval = evaluateBRDFComponents(wo, wi, material);
    return eval.diffuse + eval.specular;
}

vec3 microfacetF(vec3 wo, vec3 wi, vec3 h, Material material) {
    float NoL = cosTheta(wi);
    float NoV = cosTheta(wo);

    if (NoL <= 0.0 || NoV <= 0.0) {
        return vec3(0.0); // Below horizon - no contribution
    }

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
    float nh = max(cosTheta(h), EPS_COS);
    float voh = max(dot(wo, h), EPS_VOH);
    float D = D_GGX(nh, roughness);
    return max(D * nh / (4.0 * voh), EPS_PDF);
}

vec3 sampleGGX(vec2 random, float roughness) {
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

// Balance Heuristic
float misWeight(float pdf1, float pdf2) {
    if (pdf1 <= 0 || pdf2 <= 0) return 0.0;
    return pdf1 / (pdf1 + pdf2);
}

// Power heuristic (often better, beta = 2)
float misWeightPower(float pdf1, float pdf2) {
    if (pdf1 <= 0.0 || pdf2 <= 0.0) return 0.0;
    return (pdf1 * pdf1) / (pdf1 * pdf1 + pdf2 * pdf2);
}

LightSample sampleLight(uint lightIdx, vec3 hitPos, inout uint seed) {
    LightSample result;
    result.valid = false;

    if (lightIdx >= lights_data.lights.length()) return result;

    LightData light = lights_data.lights[lightIdx];
    ObjectData lightObject = objects_data.objects[light.object_index];
    Material lightMaterial = materials_data.materials[lightObject.material_index];

    Vertices lightVerts = Vertices(lightObject.vertex_address);
    Indices lightIndices = Indices(lightObject.index_address);

    // Select random triangle
    uint numTriangles = light.num_triangles;

    const int maxAttempts = 1;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
        uint triangleIdx = min(uint(rnd(seed) * numTriangles), numTriangles - 1);
        ivec3 ind = lightIndices.indices[triangleIdx];

        // Get triangle vertices
        Vertex v0 = lightVerts.v[ind.x];
        Vertex v1 = lightVerts.v[ind.y];
        Vertex v2 = lightVerts.v[ind.z];

        // Sample point on triangle
        float r1 = rnd(seed);
        float r2 = rnd(seed);
        float sqrtR1 = sqrt(r1);

        float u = 1.0 - sqrtR1;
        float v = sqrtR1 * (1.0 - r2);
        float w = sqrtR1 * r2;

        // Compute position and normal in local space
        vec3 localPos = u * v0.pos + v * v1.pos + w * v2.pos;
        // vec3 localNormal = normalize(u * v0.normal + v * v1.normal + w * v2.normal);
        vec3 worldV0 = vec3(light.transform * vec4(v0.pos, 1.0));
        vec3 worldV1 = vec3(light.transform * vec4(v1.pos, 1.0));
        vec3 worldV2 = vec3(light.transform * vec4(v2.pos, 1.0));

        // check if front facing triangle
        vec3 worldPos = vec3(light.transform * vec4(localPos, 1.0));
        mat3 normalMatrix = transpose(inverse(mat3(light.transform)));
        vec3 worldNormal = normalize(cross(worldV1 - worldV0, worldV2 - worldV0));
        vec3 toSurface = hitPos - worldPos;

        float cosL = dot(worldNormal, normalize(toSurface));
        if (cosL < 0) {
            cosL = abs(cosL);
            worldNormal = -worldNormal;
        }

        if (cosL > 0.0) {
            // Transform to world space
            result.position = worldPos;
            result.normal = worldNormal;

            // Calculate direction and distance
            vec3 toLight = result.position - hitPos;

            float safeDist = max(length(toLight), 0.01);
            result.distance = safeDist;
            result.direction = toLight / result.distance;
            float triangleArea = 0.5 * length(cross(worldV1 - worldV0, worldV2 - worldV0));
            float cosTheta = max(0.0, dot(-result.direction, result.normal));
            if (cosTheta <= 1e-6) continue; // Back-facing

            // Calculate PDF in solid angle measure
            float areaPdf = 1.0 / triangleArea;
            float triangleSelectionPdf = 1.0 / float(numTriangles);

            result.pdf = triangleSelectionPdf * areaPdf * (result.distance * result.distance) / cosTheta;

            result.emission = lightMaterial.emission_color * lightMaterial.emission_power;
            result.valid = true;
            result.instance_mask = light.instance_mask;
            return result;
        }
    }

    return result;
}

bool brdfHitsSelectedLightRQ(vec3 origin, vec3 dir, uint mask,
    out uint instanceCustomIndex, out uint primIdx, out float tHit)
{
    rayQueryEXT rq;
    rayQueryInitializeEXT(
        rq, topLevelAS,
        gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT,
        mask,
        origin, 0.001,
        dir, 1e20
    );

    while (rayQueryProceedEXT(rq)) { /* traverse */ }

    if (rayQueryGetIntersectionTypeEXT(rq, true)
            == gl_RayQueryCommittedIntersectionTriangleEXT)
    {
        instanceCustomIndex =
            rayQueryGetIntersectionInstanceCustomIndexEXT(rq, true);
        primIdx = rayQueryGetIntersectionPrimitiveIndexEXT(rq, true);
        tHit = rayQueryGetIntersectionTEXT(rq, true);
        return true;
    }
    return false;
}

bool isVisibleRQ(vec3 origin, vec3 target, vec3 normal, uint lightInstanceCustomIndex)
{
    float distToTarget = length(target - origin);
    float epsilon = 0.001;

    vec3 toLight = normalize(target - origin);
    vec3 offsetFrom = origin + normal * epsilon * sign(dot(normal, toLight));
    vec3 dir = target - offsetFrom;
    float dist = length(dir);
    if (dist <= 0.0) return false;
    dir /= dist;

    rayQueryEXT rq;
    rayQueryInitializeEXT(
        rq, topLevelAS,
        gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT,
        0xFFu,
        offsetFrom, 0.001,
        dir, dist * 0.999
    );

    while (rayQueryProceedEXT(rq)) { /* nothing */ }

    uint committedType = rayQueryGetIntersectionTypeEXT(rq, true);

    if (committedType == gl_RayQueryCommittedIntersectionNoneEXT)
        return true;

    if (committedType == gl_RayQueryCommittedIntersectionTriangleEXT) {
        uint instIdx = rayQueryGetIntersectionInstanceCustomIndexEXT(rq, true);
        if (instIdx == lightInstanceCustomIndex)
            return true;
    }

    return false;
}

struct BSDFSample {
    vec3 direction;
    vec3 value;
    float pdf;
    bool isSpecular;
};

struct SurfaceInteractionResult {
    vec3 brdf;
    float pdf;
    vec3 scatteredDirection;
    bool isSpecular;
    float diffusePdf;
    float specularPdf;
};

BSDFSample sampleBRDF(vec3 wo, Material material, vec2 random, mat3 basis) {
    BSDFSample result;
    float specularWeight = getSpecularProbability(material);
    float diffuseWeight = 1.0 - specularWeight;
    // Sample specular or diffuse based on the weights
    if (rnd(payload.seed) < specularWeight) {
        vec3 h = sampleGGX(random, material.roughness);
        vec3 wiLocal = reflect(-wo, h);

        if (cosTheta(wiLocal) <= 0) {
            wiLocal = generateCosineWeightedDirection(random);
            result.isSpecular = false;

            // Calculate proper diffuse BRDF with Fresnel
            vec3 hDiffuse = normalize(wo + wiLocal);
            float VoH = clamp(dot(wo, hDiffuse), 0.0, 1.0);
            vec3 F0 = mix(vec3(0.04), material.albedo, material.metallic);
            vec3 F = F_Schlick(F0, VoH);
            vec3 diffuseAlbedo = material.albedo * (1.0 - material.metallic);
            result.value = diffuseAlbedo * (vec3(1.0) - F) / M_PI;
            result.direction = wiLocal;
        } else {
            result.isSpecular = true;
            result.value = microfacetF(wo, wiLocal, h, material); // Specular value
            result.direction = wiLocal;
        }
    } else {
        // Sample diffuse (cosine-weighted)
        result.direction = generateCosineWeightedDirection(random);
        result.isSpecular = false;

        // Calculate proper diffuse BRDF with Fresnel
        vec3 h = normalize(wo + result.direction);
        float VoH = clamp(dot(wo, h), 0.0, 1.0);
        vec3 F0 = mix(vec3(0.04), material.albedo, material.metallic);
        vec3 F = F_Schlick(F0, VoH);
        vec3 diffuseAlbedo = material.albedo * (1.0 - material.metallic);
        result.value = diffuseAlbedo * (vec3(1.0) - F) / M_PI;
    }

    vec3 h = normalize(wo + result.direction);
    float specularPdf = microfacetPDF(wo, h, material.roughness);
    float diffusePdf = max(cosTheta(result.direction), 0.0) / M_PI;
    result.pdf = specularWeight * specularPdf + (1.0 - specularWeight) * diffusePdf;
    result.pdf = max(result.pdf, EPS_PDF);
    return result;
}

// Overload taking triangle area, cos at light, and dist to avoid recomputing.
float lightPdfFromTriangleHitParams(uint numTris, float triArea,
    float cosThetaLight, float dist)
{
    if (triArea <= 0.0 || cosThetaLight <= 1e-6) return 0.0;

    float triangleSelectionPdf = 1.0 / float(max(numTris, 1u));
    float areaPdf = 1.0 / max(triArea, 1e-4);
    float p_dir = triangleSelectionPdf * areaPdf * (dist * dist) / cosThetaLight;
    return max(p_dir, 1e-6);
}

// Calculate full PDF for a given direction
float calculatePDF(vec3 wo, vec3 wi, Material material) {
    BRDFEval eval = evaluateBRDFComponents(wo, wi, material);
    float specularProbability = getSpecularProbability(material);

    return specularProbability * eval.specularPdf + (1.0 - specularProbability) * eval.diffusePdf;
}

// Helper function to evaluate MIS for a specific light
vec3 evaluateLightMIS(vec3 hitPos, vec3 normal, Material material, vec3 viewDir, uint lightIdx, float lightSelectionPdf, inout uint seed) {
    vec3 radiance = vec3(0.0);

    mat3 basis = createBasis(normal);
    vec3 woLocal = worldToLocal(-viewDir, basis);

    LightData light = lights_data.lights[lightIdx];
    ObjectData lightObject = objects_data.objects[light.object_index];
    Material lightMaterial = materials_data.materials[lightObject.material_index];

    LightSample lightSample = sampleLight(lightIdx, hitPos, seed);
    vec3 wiLocal = worldToLocal(lightSample.direction, basis);

    if (lightSample.valid && cosTheta(wiLocal) > 1e-4 && isVisibleRQ(hitPos, lightSample.position, normal, light.object_index)) {
        vec3 brdf = evaluateFullBRDF(woLocal, wiLocal, material);
        float lightPdf = lightSample.pdf * lightSelectionPdf;

        #if USE_MIS
        float specularProb = getSpecularProbability(material);
        vec3 hLocal = normalize(woLocal + wiLocal);
        float specularPdf = microfacetPDF(woLocal, hLocal, material.roughness);
        float diffusePdf = cosTheta(wiLocal) / M_PI;
        float brdfPdf = specularProb * specularPdf + (1.0 - specularProb) * diffusePdf;
        float weight = misWeightPower(lightPdf, brdfPdf);
        #else
        float weight = 1.0;
        #endif

        vec3 Li = lightSample.emission;
        radiance += brdf * Li * cosTheta(wiLocal) * weight / max(lightPdf, 1e-6);
    }

    return radiance;
}

float computeLightWeight(vec3 hitPos, uint lightIdx) {
    LightData light = lights_data.lights[lightIdx];
    ObjectData lightObject = objects_data.objects[light.object_index];
    Material lightMaterial = materials_data.materials[lightObject.material_index];

    vec3 lightCenter = vec3(light.transform[3]);
    vec3 toLight = lightCenter - hitPos;
    float distanceSq = dot(toLight, toLight);

    float power = lightMaterial.emission_power;
    float distanceFactor = 1.0 / max(distanceSq, 0.001);

    return power * distanceFactor;
}

float computeTotalLightWeight(vec3 hitPos, bool skipCurrentObject) {
    int numLights = lights_data.lights.length();
    float totalWeight = 0.0;
    const int maxLights = min(numLights, MAXLIGHTS);

    for (int i = 0; i < maxLights; i++) {
        if (skipCurrentObject && gl_InstanceCustomIndexEXT == lights_data.lights[i].object_index) continue;

        totalWeight += computeLightWeight(hitPos, i);
    }

    return totalWeight;
}

float computeLightSelectionPdf(vec3 hitPos, uint lightIdx) {
    float weight = computeLightWeight(hitPos, lightIdx);
    float totalWeight = computeTotalLightWeight(hitPos, false);
    if (totalWeight <= 0.0) return 0.0;
    return weight / totalWeight;
}

vec3 estimateDirectLightingMIS_PowerImportance(vec3 hitPos, vec3 normal, Material material, vec3 viewDir, inout uint seed) {
    vec3 totalRadiance = vec3(0.0);

    int numLights = lights_data.lights.length();
    if (numLights == 0) return totalRadiance;

    float totalWeight = 0.0;
    float weights[MAXLIGHTS];
    const int maxLights = min(numLights, MAXLIGHTS);

    uint currentObjectIndex = gl_InstanceCustomIndexEXT;

    for (int i = 0; i < maxLights; i++) {
        if (currentObjectIndex == lights_data.lights[i].object_index)
            continue;

        weights[i] = computeLightWeight(hitPos, i);
        totalWeight += weights[i];
    }

    if (totalWeight <= 0.0) return totalRadiance;

    float r1 = rnd(seed) * totalWeight;
    uint selectedLight = -1;

    for (int i = 0; i < maxLights; i++) {
        r1 -= weights[i];
        if (r1 <= 0) {
            selectedLight = i;
            break;
        }
    }

    if (selectedLight == -1) return totalRadiance;

    float lightPdf = weights[selectedLight] / totalWeight;

    totalRadiance += evaluateLightMIS(hitPos, normal, material, viewDir, selectedLight, lightPdf, seed);

    return totalRadiance;
}

// Main MIS function with automatic strategy selection
vec3 estimateDirectLightingMIS(vec3 hitPos, vec3 normal, Material material, vec3 viewDir, inout uint seed) {
    return estimateDirectLightingMIS_PowerImportance(hitPos, normal, material, viewDir, seed);
}

void main() {
    ObjectData object = objects_data.objects[gl_InstanceCustomIndexEXT];
    Material mat = materials_data.materials[object.material_index];

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

    vec3 incomingRayDir = gl_WorldRayDirectionEXT;

    bool frontFacing = dot(worldNrm, -incomingRayDir) > 0.0;

    worldNrm = frontFacing ? worldNrm : -1.0 * worldNrm;

    bool isEmissive = (mat.emission_power > 0.0);

    #if USE_DIRECT_LIGHTING
    #if USE_MIS
    bool didDirectIllumination = false;
    float p_sample_light = clamp(mat.roughness, 0.1, 0.9);
    float p = rnd(payload.seed);
    if (p < p_sample_light) {
        vec3 directLight = estimateDirectLightingMIS(worldPos, worldNrm, mat, incomingRayDir, payload.seed);
        payload.color += payload.throughput * directLight / p_sample_light;
        didDirectIllumination = true;
    }
    #else
    vec3 directLight = estimateDirectLightingMIS(worldPos, worldNrm, mat, incomingRayDir, payload.seed);
    payload.color += payload.throughput * directLight;
    #endif
    #endif

    mat3 basis = createBasis(worldNrm);
    vec3 woLocal = worldToLocal(-incomingRayDir, basis);

    // Sample diffuse direction
    vec2 random = vec2(rnd(payload.seed), rnd(payload.seed));
    BSDFSample brdfSample = sampleBRDF(woLocal, mat, random, basis);

    if (isEmissive) {
        #if USE_DIRECT_LIGHTING
        #if USE_MIS
        if (payload.firstBounce || payload.isSpecular) {
            payload.color += payload.throughput * mat.emission_color * mat.emission_power;
        } else if (!payload.didDirectIllumination) {
            uint lightIdx = object.light_index;
            LightData light = lights_data.lights[lightIdx];

            if (lightIdx != -1) {
                float dist = length(worldPos - payload.previousHitPos);
                float distSq = dist * dist;

                float cosLight = max(0.0, dot(worldNrm, -incomingRayDir));

                vec3 worldV0 = vec3(light.transform * vec4(v0.pos, 1.0));
                vec3 worldV1 = vec3(light.transform * vec4(v1.pos, 1.0));
                vec3 worldV2 = vec3(light.transform * vec4(v2.pos, 1.0));

                float triangleArea = 0.5 * length(cross(worldV1 - worldV0, worldV2 - worldV0));
                uint numTriangles = light.num_triangles;

                float areaPdf = 1.0 / triangleArea;
                float triangleSelectionPdf = 1.0 / float(numTriangles);

                float pdfGeo = triangleSelectionPdf * areaPdf * distSq / cosLight;

                float lightSelectionPdf = computeLightSelectionPdf(worldPos, lightIdx);

                float lightPdf = lightSelectionPdf * pdfGeo;

                float brdfPdf = payload.previousBrdfPdf;

                float misWeight = misWeightPower(brdfPdf, lightPdf);
                payload.color += payload.throughput * mat.emission_color * mat.emission_power * misWeight / (1 - payload.p_sample_light);
            }
        }
        #else
        if (payload.firstBounce || payload.isSpecular) {
            payload.color += payload.throughput * mat.emission_color * mat.emission_power;
        }
        #endif
        #else
        payload.color += payload.throughput * mat.emission_color * mat.emission_power;
        #endif
    }

    #if USE_MIS
    payload.didDirectIllumination = didDirectIllumination;
    payload.p_sample_light = p_sample_light;
    #endif

    if (brdfSample.pdf > 0.0 && cosTheta(brdfSample.direction) > 0.0) {
        payload.throughput *= brdfSample.value * cosTheta(brdfSample.direction) / brdfSample.pdf;
        payload.nextDirection = localToWorld(brdfSample.direction, basis);
        payload.hitPosition = worldPos;
        payload.hit = true;
        payload.isSpecular = brdfSample.isSpecular;
        payload.previousBrdfPdf = brdfSample.pdf;
        payload.previousHitPos = worldPos;
    } else {
        payload.hit = false; // Terminate path
    }

    payload.firstBounce = false;
}
