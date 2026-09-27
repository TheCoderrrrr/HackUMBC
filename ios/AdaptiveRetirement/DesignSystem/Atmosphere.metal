#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Adaptive brand atmosphere.
// Broad emerald / mint fields that drift, morph and slowly shift hue,
// fading into charcoal at the edges; fine duotone grain.

namespace atmosphere {

// Integer hash — no directional banding.
float hash21(float2 p) {
    int2 i = int2(floor(p)) + int2(32768);
    uint2 q = uint2(i) * uint2(1597334673u, 3812015801u);
    uint n = (q.x ^ q.y) * 1597334673u;
    n ^= n >> 16;
    n *= 2246822519u;
    n ^= n >> 13;
    return float(n) * (1.0 / 4294967295.0);
}

float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0); // quintic: C2-smooth, no creases
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    const float2x2 rot = float2x2(0.8, -0.6, 0.6, 0.8);
    for (int i = 0; i < 4; i++) {
        v += a * valueNoise(p);
        p = rot * p * 2.03 + 11.7;
        a *= 0.5;
    }
    return v;
}

// Domain warp for the colour field.
float2 warp(float2 p, float t) {
    float2 q = float2(fbm(p * 1.6 + float2(0.0, t * 0.07)),
                      fbm(p * 1.6 + float2(5.2, -t * 0.06)));
    float2 r = float2(fbm(p * 1.2 + 3.0 * q + float2(1.7, 9.2) + t * 0.04),
                      fbm(p * 1.2 + 3.0 * q + float2(8.3, 2.8) - t * 0.035));
    return p + 0.22 * (r - 0.5);
}

half3 srgb(float r, float g, float b) { return half3(r / 255.0, g / 255.0, b / 255.0); }

float blob(float2 p, float2 c, float r) {
    float2 d = p - c;
    return exp(-dot(d, d) / (r * r));
}

} // namespace atmosphere

/// - size: view size in points.
/// - time: seconds (frozen under Reduce Motion).
/// - glow: 0…1 intensity of the colour field.
/// - grain: 0…1 grain amount.
/// - scale: display scale, for pixel-accurate grain.
[[ stitchable ]] half4 adaptiveAtmosphere(float2 position, half4 color, float2 size, float time,
                                          float glow, float grain, float scale) {
    using namespace atmosphere;

    float t = time;
    float2 uv = position / size;
    float2 p = (uv - 0.5) * float2(size.x / size.y, 1.0); // height-normalised, centred

    float2 w = warp(p, t);

    // Slow palette drift: emerald ↔ teal ↔ leaf, mint ↔ seafoam ↔ lime.
    float h1 = 0.5 + 0.5 * sin(t * 0.12);
    float h2 = 0.5 + 0.5 * sin(t * 0.095 + 2.1);
    half3 emerald  = mix(mix(srgb(47, 158, 94), srgb(38, 140, 110), h1), srgb(84, 168, 70), h2 * 0.55);
    half3 mint     = mix(mix(srgb(168, 230, 161), srgb(150, 225, 190), h2), srgb(196, 236, 150), h1 * 0.45);
    half3 deep     = mix(srgb(22, 90, 52), srgb(30, 80, 40), h1);
    half3 charcoal = srgb(16, 17, 20);

    // Drifting fields.
    float2 c1 = float2(-0.07 + 0.13 * sin(t * 0.19), 0.07 + 0.12 * cos(t * 0.15));
    float2 c2 = float2(0.08 + 0.12 * cos(t * 0.17 + 1.3), -0.07 + 0.11 * sin(t * 0.21));
    float2 c3 = float2(0.02 + 0.14 * sin(t * 0.11 + 2.4), 0.22 + 0.08 * cos(t * 0.13));
    float2 c4 = float2(-0.03 + 0.12 * cos(t * 0.09 + 4.0), -0.25 + 0.08 * sin(t * 0.12));

    float g1 = blob(w, c1, 0.34 + 0.04 * sin(t * 0.25));
    float g2 = blob(w, c2, 0.22 + 0.03 * cos(t * 0.2));
    float g3 = blob(w, c3, 0.26);
    float g4 = blob(w, c4, 0.24);

    half3 col = charcoal;
    col = mix(col, deep, half(saturate(g4 * 0.85 + g3 * 0.55)));
    col = mix(col, emerald, half(saturate(g1 * 0.92)));
    col = mix(col, mint, half(saturate(g2 * 0.72)));

    // Dissolve into charcoal at the edges.
    float edge = length(p * float2(1.55, 1.0));
    float vignette = smoothstep(0.66, 0.16, edge);
    col = mix(charcoal, col, half(vignette * glow));

    // Fine duotone grain — static, pixel-locked.
    if (grain > 0.001) {
        float n = hash21(floor(position * scale / 0.75) + 0.5);
        float darkMask = step(n, 0.39);
        float lightMask = step(0.61, n);
        col = mix(col, half3(0.0), half(darkMask * 0.045 * grain));
        col = mix(col, half3(1.0), half(lightMask * 0.035 * grain));
    }

    return half4(col, 1.0h);
}

/// Duotone grain applied to an existing fill (chart areas, cash band). Preserves alpha.
/// Dark ink 12% / warm white 10%, 85% density by default.
[[ stitchable ]] half4 fillGrain(float2 position, half4 color, float amount, float scale) {
    using namespace atmosphere;
    if (color.a < 0.001h) { return color; }
    float n = hash21(floor(position * scale / 0.7) + 0.5);
    float darkMask = step(n, 0.425);
    float lightMask = step(0.575, n);
    half3 c = color.rgb / max(color.a, 0.0001h); // unpremultiply
    c = mix(c, half3(0.04, 0.04, 0.06), half(darkMask * 0.12 * amount));
    c = mix(c, half3(1.0, 0.97, 0.93), half(lightMask * 0.10 * amount));
    return half4(c * color.a, color.a);
}

// Setup field: a flame-like gradient rising from the bottom edge only.
// Soft tongues of mint → emerald → deep forest dissolve into charcoal.

namespace ember {

// Heat: >0 inside the flame, ~1 at the hottest (bottom centre). p is height-normalised, y up from the bottom.
float heat(float2 p, float t) {
    using namespace atmosphere;
    // Vertically stretched noise → streaky, upward-flowing tongues.
    float n = fbm(float2(p.x * 3.0 + 3.1, p.y * 0.7 - t * 0.05));
    float sway = 0.02 * sin(p.y * 5.0 + t * 0.35) + 0.06 * (n - 0.5);
    // 1 − |sin| gives cusped, upward-pointing peaks; noise varies their heights.
    float peak = pow(1.0 - abs(sin((p.x + sway) * 15.0 + 0.9 + t * 0.03)), 1.2);
    float tall = 0.25 + 1.4 * fbm(float2((p.x + sway) * 4.0 + 2.3, t * 0.02));
    float height = 0.36 + 0.02 * sin(t * 0.13);
    float h = 1.0 - p.y / height + 0.30 * (peak * tall - 0.5) * smoothstep(0.02, 0.3, p.y) + 0.18 * (n - 0.5);
    // Hottest core low and centred.
    float2 core = p - float2(0.03 * sin(t * 0.17), 0.0);
    h += 0.12 * exp(-dot(core, core) / 0.05);
    return h;
}

half3 ramp(float h, float t) {
    using namespace atmosphere;
    // Same slow drift as the brand field: emerald ↔ teal ↔ leaf.
    float h1 = 0.5 + 0.5 * sin(t * 0.12);
    float h2 = 0.5 + 0.5 * sin(t * 0.095 + 2.1);
    half3 charcoal = srgb(16, 17, 20);
    half3 deep     = mix(srgb(22, 90, 52), srgb(30, 80, 40), h1);
    half3 emerald  = mix(mix(srgb(47, 158, 94), srgb(38, 140, 110), h1), srgb(84, 168, 70), h2 * 0.55);
    half3 mint     = mix(mix(srgb(168, 230, 161), srgb(150, 225, 190), h2), srgb(196, 236, 150), h1 * 0.45);
        half3 c = mix(charcoal, deep, half(smoothstep(-0.2, 0.3, h)));
    c = mix(c, emerald,  half(smoothstep(0.24, 0.62, h)));
    // Tops out at a mid mint so the green button and accent text stay legible.
    c = mix(c, mint, half(0.6 * smoothstep(0.62, 1.15, h)));
    return c;
}

} // namespace ember

/// - size: view size in points.
/// - time: seconds (frozen under Reduce Motion).
/// - grain: 0…1 grain amount.
/// - scale: display scale, for pixel-accurate grain.
[[ stitchable ]] half4 emberAtmosphere(float2 position, half4 color, float2 size, float time,
                                       float grain, float scale) {
    using namespace atmosphere;

    float t = time;
    float2 uv = position / size;
    float2 p = float2((uv.x - 0.5) * size.x / size.y, 1.0 - uv.y);

    float h = ember::heat(p, t);
    half3 col = ember::ramp(h, t);

    if (grain > 0.001) {
        float n = hash21(floor(position * scale / 0.75) + 0.5);
        float darkMask = step(n, 0.39);
        float lightMask = step(0.61, n);
        col = mix(col, half3(0.0), half(darkMask * 0.05 * grain));
        col = mix(col, half3(1.0), half(lightMask * 0.035 * grain));
    }

    return half4(col, 1.0h);
}
