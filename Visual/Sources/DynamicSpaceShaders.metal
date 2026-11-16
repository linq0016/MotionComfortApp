#include <metal_stdlib>
using namespace metal;

// 星点顶点：positionAndSize 为像素 x/y、尺寸、透明度；color.xyz 为 RGB，w 未使用。
struct DynamicSpriteVertex {
    float4 positionAndSize;
    float4 color;
};

// 星云顶点：positionAndUV 为像素 x/y 与局部 u/v，colorAndAlpha 为 RGBA，atlasAndMisc.x 为图集索引。
struct DynamicNebulaQuadVertex {
    float4 positionAndUV;
    float4 colorAndAlpha;
    float4 atlasAndMisc;
};

struct DynamicViewportUniforms {
    float2 viewportSize;
    float2 atlasGrid;
    float nebulaAtlasInset;
};

struct DynamicVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

struct DynamicNebulaVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float atlasIndex;
};

// 顶点阶段把左上角为原点的像素坐标转换为 Metal 的标准化设备坐标。
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
        inVertex.color.xyz,
        inVertex.positionAndSize.w
    );
    return outVertex;
}

vertex DynamicNebulaVertexOut dynamicNebulaQuadVertex(
    const device DynamicNebulaQuadVertex *vertices [[buffer(0)]],
    constant DynamicViewportUniforms &uniforms [[buffer(1)]],
    uint vertexID [[vertex_id]]
) {
    DynamicNebulaQuadVertex inVertex = vertices[vertexID];
    float2 viewport = uniforms.viewportSize;
    float2 pixelPosition = inVertex.positionAndUV.xy;

    float2 ndc = float2(
        ((pixelPosition.x / viewport.x) * 2.0) - 1.0,
        1.0 - ((pixelPosition.y / viewport.y) * 2.0)
    );

    DynamicNebulaVertexOut outVertex;
    outVertex.position = float4(ndc, 0.0, 1.0);
    outVertex.uv = inVertex.positionAndUV.zw;
    outVertex.color = inVertex.colorAndAlpha;
    outVertex.atlasIndex = inVertex.atlasAndMisc.x;
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

// 按图集索引采样单朵星云，应用内缩采样范围和透明边缘过渡。
fragment half4 dynamicNebulaQuadFragment(
    DynamicNebulaVertexOut inFragment [[stage_in]],
    texture2d<half> spriteTexture [[texture(0)]],
    constant DynamicViewportUniforms &uniforms [[buffer(1)]]
) {
    constexpr sampler textureSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );

    float2 atlasGrid = max(uniforms.atlasGrid, float2(1.0, 1.0));
    int atlasColumns = max(int(atlasGrid.x), 1);
    int atlasRows = max(int(atlasGrid.y), 1);
    int atlasIndex = clamp(int(round(inFragment.atlasIndex)), 0, atlasColumns * atlasRows - 1);
    int atlasColumn = atlasIndex % atlasColumns;
    int atlasRow = atlasIndex / atlasColumns;

    float2 tileSize = float2(1.0 / float(atlasColumns), 1.0 / float(atlasRows));
    float2 safePoint = clamp(inFragment.uv, float2(0.0), float2(1.0));
    float2 tileInset = float2(uniforms.nebulaAtlasInset, uniforms.nebulaAtlasInset);
    float2 atlasCoord = (float2(atlasColumn, atlasRow) + tileInset + safePoint * (float2(1.0) - tileInset * 2.0)) * tileSize;
    half4 sampled = spriteTexture.sample(textureSampler, atlasCoord);

    half brightness = half(inFragment.color.a);
    return half4(
        half3(inFragment.color.rgb) * sampled.rgb * brightness,
        sampled.a * brightness
    );
}
