#include <metal_stdlib>
using namespace metal;

struct DynamicSpriteVertex {
    float4 positionAndSize;
    float4 colorAndSoftness;
};

struct DynamicViewportUniforms {
    float2 viewportSize;
};

struct DynamicVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

vertex DynamicVertexOut dynamicSpriteVertex(
    const device DynamicSpriteVertex *vertices [[buffer(0)]],
    constant DynamicViewportUniforms &uniforms [[buffer(1)]],
    uint vertexID [[vertex_id]]
) {
    DynamicSpriteVertex inVertex = vertices[vertexID];
    float2 viewport = uniforms.viewportSize;
    float2 pixelPosition = inVertex.positionAndSize.xy;

    float2 ndc = float2(
        ((pixelPosition.x / viewport.x) * 2.0) - 1.0,
        1.0 - ((pixelPosition.y / viewport.y) * 2.0)
    );

    DynamicVertexOut outVertex;
    outVertex.position = float4(ndc, 0.0, 1.0);
    outVertex.pointSize = max(inVertex.positionAndSize.z, 1.0);
    outVertex.color = float4(
        inVertex.colorAndSoftness.xyz,
        inVertex.positionAndSize.w
    );
    return outVertex;
}

fragment half4 dynamicSpriteFragment(
    DynamicVertexOut inFragment [[stage_in]],
    texture2d<half> spriteTexture [[texture(0)]],
    float2 pointCoord [[point_coord]]
) {
    constexpr sampler textureSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );

    half4 sampled = spriteTexture.sample(textureSampler, pointCoord);
    return half4(
        half3(inFragment.color.rgb) * sampled.rgb * half(inFragment.color.a),
        sampled.a * half(inFragment.color.a)
    );
}
