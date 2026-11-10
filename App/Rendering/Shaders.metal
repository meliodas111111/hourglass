//  Shaders.metal — hourglass renderer.
//
//  One full-screen triangle; everything (sand, glass, frame) is composed in the fragment shader:
//    • sand: RG8Uint grid texture (type, shade) read with nearest sampling; shade → palette slot + ±8 % noise;
//    • glass: RG8Snorm field (signed distance, horizontal coordinate) → rim light, Fresnel, highlights, reflection;
//    • frame: wooden caps top/bottom + two side posts.
//  The viewport has the grid's 1:2 aspect; `angle` rotates (and fits) the hourglass for flip animations.
//  Output is premultiplied alpha over the SwiftUI background.

#include <metal_stdlib>
using namespace metal;

struct SandUniforms {
    float4 palette[5];
    float2 gridSize;
    float  capRows;
    float  time;
    float  glow;      // 0…1 "last grains" finish pulse
    float  gateRow;
    float  centerX;
    float  angle;     // radians, flip animation
};

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

vertex VSOut sandVertex(uint vid [[vertex_id]]) {
    // Full-screen triangle.
    float2 p = float2((vid << 1) & 2, vid & 2);
    VSOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float4 wood(float2 g, float edgeT, float2 gridSize) {
    float grain = sin(g.x * 0.21 + sin(g.y * 0.9) * 1.7) * 0.05 + (hash21(floor(g)) - 0.5) * 0.04;
    float bevel = mix(0.62, 1.0, smoothstep(0.0, 0.45, edgeT)) * mix(1.0, 0.8, smoothstep(0.55, 1.0, edgeT));
    float3 base = float3(0.50, 0.31, 0.17) * (bevel + grain);
    return float4(base, 1.0);
}

fragment float4 sandFragment(VSOut in [[stage_in]],
                             texture2d<uint, access::read> sand [[texture(0)]],
                             texture2d<float> glass [[texture(1)]],
                             constant SandUniforms &u [[buffer(0)]]) {
    // Viewport has the grid's aspect. During a flip the hourglass is rotated about its centre and scaled so the
    // rotated silhouette always fits the viewport (half size when horizontal) — reads as a 3-D turn.
    float aspect = u.gridSize.x / u.gridSize.y;
    float2 q = float2((in.uv.x - 0.5) * aspect, in.uv.y - 0.5);  // physical units, height = 1
    float sn = sin(-u.angle), cs = cos(-u.angle);
    float fit = min(aspect / (aspect * abs(cs) + abs(sn)), 1.0 / (aspect * abs(sn) + abs(cs)));
    q = float2(cs * q.x - sn * q.y, sn * q.x + cs * q.y) / fit;
    float2 guv = float2(q.x / aspect + 0.5, q.y + 0.5);          // 0…1 over the grid
    if (any(guv < 0.0) || any(guv > 1.0)) { return float4(0.0); }
    float2 g = guv * u.gridSize;                                  // cell units

    // ---- Frame (caps + posts) ----
    float relX = abs(g.x - u.centerX) / u.gridSize.x;             // 0 … 0.5
    float capT = u.capRows;
    if ((g.y < capT || g.y > u.gridSize.y - capT) && relX < 0.49) {
        float t = g.y < capT ? g.y / capT : (u.gridSize.y - g.y) / capT;
        return wood(g, t, u.gridSize);
    }
    if (relX > 0.462 && relX < 0.484) {
        float across = (relX - 0.462) / 0.022;                    // 0…1 across the post
        float4 w = wood(g * float2(0.3, 1.0), 0.5, u.gridSize);
        w.rgb *= 0.65 + 0.45 * sin(across * M_PI_F);              // cylindrical shading
        return w;
    }

    // ---- Glass field ----
    constexpr sampler lin(filter::linear, address::clamp_to_edge);
    float2 field = glass.sample(lin, guv).rg;
    float d = field.r * 8.0;                                      // signed distance (cells), < 0 inside
    float hx = field.g;                                           // −1 … 1 across the bulb

    float4 col = float4(0.0);

    if (d < 0.0) {
        // Back wall of the glass: faint cool tint.
        col = float4(0.80, 0.88, 1.0, 1.0) * 0.05;

        uint2 cell = uint2(clamp(g, float2(0.0), u.gridSize - 1.0));
        uint2 cs = sand.read(cell).rg;
        if (cs.r == 1u) {
            uint slot = min(cs.g >> 5, 4u);
            float noise = float(cs.g & 31u) / 31.0;
            float3 base = u.palette[slot].rgb * (0.92 + 0.16 * noise);   // ±8 % brightness
            // Contact shadow near the glass and a soft top light.
            float ao = 1.0 - 0.22 * smoothstep(-4.0, 0.0, d);
            float3 sandCol = base * ao;
            // Finish pulse: warm glow.
            sandCol += u.glow * 0.35 * u.palette[2].rgb;
            col = float4(sandCol, 1.0);
        }
    }

    // ---- Glass front: rim, Fresnel, highlights, reflection ----
    float rim = exp(-abs(d) * 1.1) * 0.55;
    float inside = step(d, 0.0);
    float fresnel = pow(saturate(abs(hx)), 6.0) * 0.30 * inside;
    float vy = guv.y;
    float neckFade = smoothstep(0.02, 0.10, abs(vy - 0.5));
    float streak = (exp(-pow((hx + 0.58) / 0.07, 2.0)) * 0.30 +
                    exp(-pow((hx - 0.66) / 0.035, 2.0)) * 0.12) * neckFade * inside;
    float reflection = 0.06 * (1.0 - vy) * inside * (0.5 + 0.5 * hx);
    float thickness = (d > 0.0 && d < 2.2) ? 0.18 : 0.0;           // glass wall itself
    float a = saturate(rim + fresnel + streak + reflection + thickness);

    // Premultiplied "over": white highlight on top of sand / tint.
    col.rgb = col.rgb * (1.0 - a * 0.6) + float3(1.0) * a;
    col.a = saturate(max(col.a, a));
    col.rgb = min(col.rgb, float3(col.a));
    return col;
}
