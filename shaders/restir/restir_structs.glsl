struct RTXDI_DIReservoir {
    float weightSum; // W_sum: Sum of all weights processed(wsum)
    float targetPdf; // Target PDF for selected sample
    uint M; // Number of samples processed so far

    uint lightIndex; // Index of selected light
    vec2 uv; // UV coordinates on light surface(specially for area lights)
    float distance;
    float W; // Final contribution weight;
};

RTXDI_DIReservoir RTXDI_EmptyDIReservoir() {
    RTXDI_DIReservoir reservoir;
    reservoir.weightSum = 0.0;
    reservoir.targetPdf = 0.0;
    reservoir.M = 0;
    reservoir.lightIndex = ~0u; // Invalid light index
    reservoir.uv = vec2(0.0);
    reservoir.distance = 0.0;
    reservoir.W = 0.0;
    // reservoir.cachedFlags = 0;
    return reservoir;
}
