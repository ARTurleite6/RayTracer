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
    bool valid;
};

struct BRDFEval {
    vec3 diffuse; // Diffuse component
    vec3 specular; // Specular component
    float diffusePdf;
    float specularPdf;
};

// Get selection probability for specular vs diffuse sampling
float getSpecularProbability(Material material) {
    vec3 F0 = mix(vec3(0.04), material.albedo, material.metallic);
    return max3(F0);
}

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

    // Calculate diffuse term (Lambert)
    float nonMetalWeight = 1.0 - material.metallic;
    result.diffuse = material.albedo * nonMetalWeight / M_PI;
    result.diffusePdf = NoL / M_PI;

    // Calculate specular microfacet term
    // D term (normal distribution function)
    float D = D_GGX(NoH, material.roughness);

    // G term (geometric shadowing)
    float G = G_Smith(NoV, NoL, material.roughness);

    // Fresnel term
    vec3 F0 = mix(vec3(0.04), material.albedo, material.metallic);
    vec3 F = F_Schlick(F0, VoH);

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
    float NoH = cosTheta(h);
    float VoH = dot(wo, h);

    float D = D_GGX(NoH, roughness);

    return D * NoH / (4.0 * VoH);
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
    vec3 localNormal = normalize(u * v0.normal + v * v1.normal + w * v2.normal);

    // Transform to world space
    result.position = vec3(light.transform * vec4(localPos, 1.0));
    mat3 normalMatrix = transpose(inverse(mat3(light.transform)));
    result.normal = normalize(normalMatrix * localNormal);

    // Calculate direction and distance
    vec3 toLight = result.position - hitPos;
    result.distance = length(toLight);
    result.direction = toLight / result.distance;

    // Calculate triangle area in world space
    vec3 worldV0 = vec3(light.transform * vec4(v0.pos, 1.0));
    vec3 worldV1 = vec3(light.transform * vec4(v1.pos, 1.0));
    vec3 worldV2 = vec3(light.transform * vec4(v2.pos, 1.0));
    float triangleArea = 0.5 * length(cross(worldV1 - worldV0, worldV2 - worldV0));

    // Calculate PDF in solid angle measure
    float cosTheta = max(0.0, dot(-result.direction, result.normal));
    if (cosTheta <= 1e-8) return result; // Back-facing

    float areaPdf = 1.0 / triangleArea;
    float triangleSelectionPdf = 1.0 / float(numTriangles);
    result.pdf = triangleSelectionPdf * areaPdf * (result.distance * result.distance) / cosTheta;

    result.emission = lightMaterial.emission_color * lightMaterial.emission_power;
    result.valid = true;

    return result;
}

// Test visibility between two points
bool isVisible(vec3 from, vec3 to, vec3 normal) {
    vec3 direction = to - from;
    float distance = length(direction);
    direction /= distance;

    vec3 offsetFrom = from + normal * 0.001;

    isShadowed = true;
    traceRayEXT(
        topLevelAS,
        gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT | gl_RayFlagsSkipClosestHitShaderEXT,
        0xFF,
        0, 0, 1,
        offsetFrom,
        0.001,
        direction,
        distance * 0.999,
        1
    );

    return !isShadowed;
}

// MIS direct lighting estimation
vec3 estimateDirectLightingMIS(vec3 hitPos, vec3 normal, Material material, vec3 viewDir, inout uint seed) {
    vec3 totalRadiance = vec3(0.0);

    int numLights = lights_data.lights.length();
    if (numLights == 0) return totalRadiance;

    mat3 basis = createBasis(normal);
    vec3 woLocal = worldToLocal(-viewDir, basis);

    // Light selection (simplified - pick random light)
    uint lightIdx = min(uint(rnd(seed) * numLights), uint(numLights - 1));
    float lightSelectionPdf = 1.0 / float(numLights);

    // Strategy 1: BRDF Sampling
    {
        float specularProb = getSpecularProbability(material);

        vec3 wiLocal;
        float brdfPdf;
        bool isSpecular = false;

        // Sample BRDF
        if (rnd(seed) < specularProb) {
            // Sample GGX specular
            vec3 h = sampleGGX(vec2(rnd(seed), rnd(seed)), material.roughness);
            wiLocal = reflect(-woLocal, h);
            brdfPdf = microfacetPDF(woLocal, h, material.roughness) * specularProb;
            isSpecular = true;
        } else {
            // Sample Lambert diffuse
            wiLocal = generateCosineWeightedDirection(vec2(rnd(seed), rnd(seed)));
            brdfPdf = (cosTheta(wiLocal) / M_PI) * (1.0 - specularProb);
        }

        if (cosTheta(wiLocal) > 0.0 && brdfPdf > 0.0) {
            vec3 wiWorld = localToWorld(wiLocal, basis);

            // Check if this direction hits our chosen light
            // (Simplified - in practice you'd trace a ray and check what it hits)
            LightSample lightSample = sampleLight(lightIdx, hitPos, seed);

            if (lightSample.valid) {
                // Check if directions are similar (within some tolerance)
                float dirSimilarity = dot(wiWorld, lightSample.direction);

                if (dirSimilarity > 0.99 && isVisible(hitPos, lightSample.position, normal)) {
                    // Calculate light PDF for this direction
                    float lightPdf = lightSample.pdf * lightSelectionPdf;

                    // Evaluate BRDF
                    vec3 brdf = evaluateFullBRDF(woLocal, wiLocal, material);

                    // MIS weight
                    float weight = misWeightPower(brdfPdf, lightPdf);

                    vec3 Li = lightSample.emission;
                    totalRadiance += brdf * Li * cosTheta(wiLocal) * weight / brdfPdf;
                }
            }
        }
    }

    // Strategy 2: Light Sampling
    {
        LightSample lightSample = sampleLight(lightIdx, hitPos, seed);

        if (lightSample.valid && dot(lightSample.direction, normal) > 0.0) {
            if (isVisible(hitPos, lightSample.position, normal)) {
                vec3 wiLocal = worldToLocal(lightSample.direction, basis);

                if (cosTheta(wiLocal) > 0.0) {
                    // Calculate BRDF PDF for this direction
                    vec3 hLocal = normalize(woLocal + wiLocal);
                    float specularProb = getSpecularProbability(material);
                    float specularPdf = microfacetPDF(woLocal, hLocal, material.roughness);
                    float diffusePdf = cosTheta(wiLocal) / M_PI;
                    float brdfPdf = specularProb * specularPdf + (1.0 - specularProb) * diffusePdf;

                    if (brdfPdf > 0.0) {
                        // Evaluate BRDF
                        vec3 brdf = evaluateFullBRDF(woLocal, wiLocal, material);

                        // Light PDF
                        float lightPdf = lightSample.pdf * lightSelectionPdf;

                        // MIS weight
                        float weight = misWeightPower(lightPdf, brdfPdf);

                        vec3 Li = lightSample.emission;
                        totalRadiance += brdf * Li * cosTheta(wiLocal) * weight / lightPdf;
                    }
                }
            }
        }
    }

    return totalRadiance;
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
        result.isSpecular = true;
        result.value = microfacetF(wo, wiLocal, h, material); // Specular value
        result.direction = wiLocal;
    } else {
        result.direction = generateCosineWeightedDirection(random);
        result.isSpecular = false;
        result.value = material.albedo / M_PI;
    }

    vec3 h = normalize(wo + result.direction);
    float specularPdf = microfacetPDF(wo, h, material.roughness);
    float diffusePdf = cosTheta(result.direction) / M_PI;
    result.pdf = specularWeight * specularPdf + diffuseWeight * diffusePdf;
    return result;
}

vec3 sampleDirectLighting(vec3 hitPos, vec3 normal, Material material, vec3 viewDir, uint seed) {
    vec3 directIllumination = vec3(0.0);

    int numLights = lights_data.lights.length();
    if (numLights == 0) return directIllumination;

    const float ORIGIN_OFFSET = 0.001;
    vec3 offsetHitPos = hitPos + normal * ORIGIN_OFFSET;

    mat3 basis = createBasis(normal);
    vec3 woLocal = worldToLocal(-viewDir, basis);

    float totalWeight = 0.0;
    float weights[16];

    for (int i = 0; i < min(numLights, 16); i++) {
        LightData light = lights_data.lights[i];
        ObjectData lightObject = objects_data.objects[light.object_index];
        Material lightMaterial = materials_data.materials[lightObject.material_index];

        vec3 lightCenter = vec3(light.transform[3]);
        float distSq = max(0.01, dot(lightCenter - hitPos, lightCenter - hitPos));
        float power = lightMaterial.emission_power;
        float weight = power / distSq;
        weights[i] = weight;
        totalWeight += weight;
    }

    float r = rnd(seed) * totalWeight;
    float accum = 0.0;
    int chosenLightIdx = 0;

    for (int i = 0; i < min(numLights, 16); i++) {
        accum += weights[i];
        if (r <= accum) {
            chosenLightIdx = i;
            break;
        }
    }

    LightData light = lights_data.lights[chosenLightIdx];
    ObjectData lightObject = objects_data.objects[light.object_index];
    Material lightMaterial = materials_data.materials[lightObject.material_index];

    // Calculate selection probability
    float selectionPdf = totalWeight > 0.0 ? weights[chosenLightIdx] / totalWeight : 1.0;

    vec3 F0 = mix(vec3(0.04), material.albedo, material.metallic);

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
    if (NdotL <= 0.0) return vec3(0.0); // Light is behind the surface

    // Check if surface is visible from the light's perspective
    float LdotN = max(dot(-lightDir, worldLightNormal), 0.0);
    if (LdotN <= 0.001) return vec3(0.0); // Surface is behind the light

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

        if (cosTheta(wiLocal) <= 0) return vec3(0.0);

        vec3 hLocal = normalize(woLocal + wiLocal);
        float nonMetalWeight = 1.0 - material.metallic;

        vec3 specular = microfacetF(woLocal, wiLocal, hLocal, material);

        vec3 diffuse = material.albedo * nonMetalWeight / M_PI;

        vec3 brdf = diffuse + specular;

        float attenuation = 1.0;
        float NdotL = cosTheta(wiLocal);
        float LdotN = max(dot(-lightDir, worldLightNormal), 0.0);

        vec3 worldV0 = vec3(light.transform * vec4(v0.pos, 1.0));
        vec3 worldV1 = vec3(light.transform * vec4(v1.pos, 1.0));
        vec3 worldV2 = vec3(light.transform * vec4(v2.pos, 1.0));
        float triangleArea = 0.5 * length(cross(worldV1 - worldV0, worldV2 - worldV0));
        float triangleSelectionPdf = 1.0 / float(num_triangles);
        float areaPdf = 1.0 / triangleArea;
        float cosTheta = abs(LdotN);
        if (cosTheta <= 1e-8) return vec3(0);
        float solidAnglePdf = areaPdf * lightDistSq / cosTheta;
        float lightContribPdf = selectionPdf * triangleSelectionPdf; // * solidAnglePdf;

        vec3 emission = lightMaterial.emission_color * lightMaterial.emission_power;
        directIllumination = (emission * brdf * NdotL * LdotN) / lightContribPdf;
    }

    return directIllumination;
}

// Calculate full PDF for a given direction
float calculatePDF(vec3 wo, vec3 wi, Material material) {
    BRDFEval eval = evaluateBRDFComponents(wo, wi, material);
    float specularProbability = getSpecularProbability(material);

    return specularProbability * eval.specularPdf + (1.0 - specularProbability) * eval.diffusePdf;
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
    vec3 worldNrm = normalize(transpose(inverse(mat3(gl_ObjectToWorldEXT))) * norm);

    vec3 incomingRayDir = gl_WorldRayDirectionEXT;

    bool frontFacing = dot(worldNrm, -incomingRayDir) > 0.0;

    worldNrm = frontFacing ? worldNrm : -1.0 * worldNrm;

    bool isEmissive = (mat.emission_power > 0.0);

    if (isEmissive && (payload.firstBounce || payload.isSpecular)) {
        // If the material is emissive and this is the first bounce or a specular reflection,
        // we handle it differently to avoid double counting emission.
        payload.color += payload.throughput * mat.emission_color * mat.emission_power;
    }

    vec3 directLight = vec3(0);
    // if (payload.firstBounce || !payload.isSpecular) {
    // if (getSpecularProbability(mat) < 0.95) {
    directLight = estimateDirectLightingMIS(worldPos, worldNrm, mat, incomingRayDir, seed);
    // }
    // }

    payload.color += payload.throughput * directLight;

    mat3 basis = createBasis(worldNrm);
    vec3 woLocal = worldToLocal(-incomingRayDir, basis);

    // Sample diffuse direction
    vec2 random = vec2(rnd(payload.seed), rnd(payload.seed));
    BSDFSample brdfSample = sampleBRDF(woLocal, mat, random, basis);

    if (brdfSample.pdf > 0.0 && cosTheta(brdfSample.direction) > 0.0) {
        payload.throughput *= brdfSample.value * cosTheta(brdfSample.direction) / brdfSample.pdf;
        payload.nextDirection = localToWorld(brdfSample.direction, basis);
        payload.hitPosition = worldPos;
        payload.hit = true;
        payload.isSpecular = brdfSample.isSpecular;
    } else {
        payload.hit = false; // Terminate path
    }

    payload.firstBounce = false;
    //
    // payload.throughput *= brdfSample.value * cosTheta(brdfSample.direction) / brdfSample.pdf;
    // payload.nextDirection = localToWorld(brdfSample.direction, basis);
    // payload.hitPosition = worldPos;
    // payload.hit = true;
    // payload.isSpecular = brdfSample.isSpecular;
}
