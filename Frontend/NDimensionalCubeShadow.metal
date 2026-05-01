#include <metal_stdlib>
using namespace metal;

struct NDimensionalCubeShadowUniforms {
    float4 axis01;
    float4 axis23;
    float4 axis4;
};

struct NDimensionalCubeShadowVertexOut {
    float4 position [[position]];
    float2 planePosition;
};

vertex NDimensionalCubeShadowVertexOut nDimensionalCubeShadowVertex(
    uint vertexID [[vertex_id]],
    constant NDimensionalCubeShadowUniforms &uniforms [[buffer(0)]]
) {
    const float2 positions[4] = {
        float2(-1.0, -1.0),
        float2(1.0, -1.0),
        float2(-1.0, 1.0),
        float2(1.0, 1.0)
    };

    NDimensionalCubeShadowVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.planePosition = positions[vertexID];
    return out;
}

static float2 nDimensionalCubeAxis(int axis, constant NDimensionalCubeShadowUniforms &uniforms) {
    switch (axis) {
    case 0:
        return uniforms.axis01.xy;
    case 1:
        return uniforms.axis01.zw;
    case 2:
        return uniforms.axis23.xy;
    case 3:
        return uniforms.axis23.zw;
    default:
        return uniforms.axis4.xy;
    }
}

static float faceCoverage(float2 point, float2 center, float2 firstAxis, float2 secondAxis) {
    float2 relative = point - center;
    float determinant = firstAxis.x * secondAxis.y - firstAxis.y * secondAxis.x;
    if (abs(determinant) < 0.00001) {
        return 0.0;
    }

    float firstCoordinate = (relative.x * secondAxis.y - relative.y * secondAxis.x) / determinant;
    float secondCoordinate = (firstAxis.x * relative.y - firstAxis.y * relative.x) / determinant;
    float edgeDistance = max(abs(firstCoordinate), abs(secondCoordinate));
    float antialiasWidth = 0.015;
    return 1.0 - smoothstep(1.0 - antialiasWidth, 1.0 + antialiasWidth, edgeDistance);
}

fragment float4 nDimensionalCubeShadowFragment(
    NDimensionalCubeShadowVertexOut in [[stage_in]],
    constant NDimensionalCubeShadowUniforms &uniforms [[buffer(0)]]
) {
    constexpr int dimension = 5;
    float accumulatedAlpha = 0.0;

    for (int firstAxisIndex = 0; firstAxisIndex < dimension - 1; firstAxisIndex++) {
        for (int secondAxisIndex = firstAxisIndex + 1; secondAxisIndex < dimension; secondAxisIndex++) {
            float2 firstAxis = nDimensionalCubeAxis(firstAxisIndex, uniforms);
            float2 secondAxis = nDimensionalCubeAxis(secondAxisIndex, uniforms);
            int fixedAxisCount = dimension - 2;
            int fixedCombinationCount = 1 << fixedAxisCount;

            for (int fixedMask = 0; fixedMask < fixedCombinationCount; fixedMask++) {
                float2 center = float2(0.0);
                int fixedBitIndex = 0;

                for (int axisIndex = 0; axisIndex < dimension; axisIndex++) {
                    if (axisIndex == firstAxisIndex || axisIndex == secondAxisIndex) {
                        continue;
                    }

                    float sign = (fixedMask & (1 << fixedBitIndex)) == 0 ? -1.0 : 1.0;
                    center += sign * nDimensionalCubeAxis(axisIndex, uniforms);
                    fixedBitIndex += 1;
                }

                float coverage = faceCoverage(in.planePosition, center, firstAxis, secondAxis);
                accumulatedAlpha = 1.0 - (1.0 - accumulatedAlpha) * (1.0 - coverage * 0.038);
            }
        }
    }

    float3 backgroundColor = float3(0.96, 0.96, 0.94);
    float3 faceColor = float3(0.04, 0.07, 0.13);
    float3 color = mix(backgroundColor, faceColor, accumulatedAlpha);
    return float4(color, 1.0);
}
