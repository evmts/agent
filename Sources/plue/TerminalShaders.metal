#include <metal_stdlib>
using namespace metal;

// Vertex structure
struct Vertex {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

// Data passed from vertex to fragment shader
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Vertex shader
vertex VertexOut terminalVertexShader(Vertex in [[stage_in]],
                                      constant float4x4 &transform [[buffer(1)]]) {
    VertexOut out;
    
    // Apply transformation matrix
    out.position = transform * float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    
    return out;
}

// Fragment shader for background cells
fragment float4 terminalBackgroundFragment(VertexOut in [[stage_in]],
                                          constant float4 &color [[buffer(0)]]) {
    return color;
}

// Fragment shader for text glyphs
fragment float4 terminalTextFragment(VertexOut in [[stage_in]],
                                    texture2d<float> glyphTexture [[texture(0)]],
                                    constant float4 &textColor [[buffer(0)]],
                                    constant float4 &backgroundColor [[buffer(1)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    // Sample the glyph texture
    float alpha = glyphTexture.sample(textureSampler, in.texCoord).r;
    
    // Blend text color with background
    return mix(backgroundColor, textColor, alpha);
}

// Fragment shader for cursor
fragment float4 terminalCursorFragment(VertexOut in [[stage_in]],
                                      constant float4 &cursorColor [[buffer(0)]],
                                      constant float &time [[buffer(1)]]) {
    // Blinking cursor effect
    float alpha = abs(sin(time * 3.14159));
    return float4(cursorColor.rgb, cursorColor.a * alpha);
}

// Fragment shader for selection
fragment float4 terminalSelectionFragment(VertexOut in [[stage_in]],
                                         constant float4 &selectionColor [[buffer(0)]]) {
    return selectionColor;
}