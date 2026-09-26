#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Adaptive brand atmosphere.
// Broad indigo / lavender fields that drift, morph and slowly shift hue,
// fading into charcoal at the edges; sixteen organic contour rings derived
// from the same warped field; fine duotone grain.

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

// Domain warp shared by the colour field and the contours, so lines and glow morph together.
float2 warp(float2 p, float t) {
    float2 q = float2(fbm(p * 1.6 + float2(0.0, t * 0.035)),
                      fbm(p * 1.6 + float2(5.2, -t * 0.03)));
    float2 r = float2(fbm(p * 1.2 + 3.0 * q + float2(1.7, 9.2) + t * 0.018),
                      fbm(p * 1.2 + 3.0 * q + float2(8.3, 2.8) - t * 0.015));
    return p + 0.16 * (r - 0.5);
}

// Low-frequency, two-octave noise for contours so rings stay smooth and organic.
float softNoise(float2 p) {
    return 0.65 * valueNoise(p) + 0.35 * valueNoise(p * 1.9 + 7.3);
}

float2 softWarp(float2 p, float t) {
    float2 q = float2(softNoise(p * 1.4 + float2(0.0, t * 0.035)),
                      softNoise(p * 1.4 + float2(5.2, -t * 0.03)));
    return p + 0.13 * (q - 0.5);
}

// Organic radial height field for the contour rings.
float ringField(float2 p, float t) {
    float2 w = softWarp(p, t);
    float2 c = float2(0.012 * sin(t * 0.07), 0.018 * cos(t * 0.05) - 0.01);
    float2 d = (w - c) * float2(1.0, 0.86);
    float breathe = 0.006 * sin(t * 0.21);
    return length(d) + 0.035 * (softNoise(w * 2.2 - t * 0.02) - 0.5) + breathe;
}

half3 srgb(float r, float g, float b) { return half3(r / 255.0, g / 255.0, b / 255.0); }

float blob(float2 p, float2 c, float r) {
    float2 d = p - c;
    return exp(-dot(d, d) / (r * r));
}

} // namespace atmosphere

/// - size: view size in points.
/// - time: seconds (frozen under Reduce Motion).
/// - contours: 0…1 opacity of the contour layer.
/// - glow: 0…1 intensity of the colour field.
/// - grain: 0…1 grain amount.
/// - scale: display scale, for pixel-accurate grain.
[[ stitchable ]] half4 adaptiveAtmosphere(float2 position, half4 color, float2 size, float time,
                                          float contours, float glow, float grain, float scale) {
    using namespace atmosphere;

    float t = time;
    float2 uv = position / size;
    float2 p = (uv - 0.5) * float2(size.x / size.y, 1.0); // height-normalised, centred

    float2 w = warp(p, t);

    // Slow palette drift: indigo ↔ ultramarine ↔ violet, lavender ↔ periwinkle ↔ lilac.
    float h1 = 0.5 + 0.5 * sin(t * 0.045);
    float h2 = 0.5 + 0.5 * sin(t * 0.037 + 2.1);
    half3 indigo   = mix(mix(srgb(73, 89, 204), srgb(52, 86, 214), h1), srgb(98, 76, 214), h2 * 0.55);
    half3 lavender = mix(mix(srgb(169, 171, 255), srgb(150, 182, 255), h2), srgb(196, 170, 255), h1 * 0.45);
    half3 deep     = mix(srgb(40, 46, 140), srgb(62, 40, 138), h1);
    half3 charcoal = srgb(16, 17, 20);

    // Drifting fields.
    float2 c1 = float2(-0.07 + 0.06 * sin(t * 0.11), 0.07 + 0.06 * cos(t * 0.083));
    float2 c2 = float2(0.08 + 0.05 * cos(t * 0.097 + 1.3), -0.07 + 0.05 * sin(t * 0.12));
    float2 c3 = float2(0.02 + 0.08 * sin(t * 0.061 + 2.4), 0.22 + 0.04 * cos(t * 0.074));
    float2 c4 = float2(-0.03 + 0.06 * cos(t * 0.052 + 4.0), -0.25 + 0.04 * sin(t * 0.066));

    float g1 = blob(w, c1, 0.34 + 0.02 * sin(t * 0.17));
    float g2 = blob(w, c2, 0.22 + 0.015 * cos(t * 0.13));
    float g3 = blob(w, c3, 0.26);
    float g4 = blob(w, c4, 0.24);

    half3 col = charcoal;
    col = mix(col, deep, half(saturate(g4 * 0.85 + g3 * 0.55)));
    col = mix(col, indigo, half(saturate(g1 * 0.92)));
    col = mix(col, lavender, half(saturate(g2 * 0.72)));

    // Dissolve into charcoal at the edges.
    float edge = length(p * float2(1.55, 1.0));
    float vignette = smoothstep(0.66, 0.16, edge);
    col = mix(charcoal, col, half(vignette * glow));

    // Contour rings: 16 nested rings, analytic pixel-space anti-aliasing.
    if (contours > 0.001) {
        const float spacing = 0.026;
        const float inner = 0.05;
        const float outer = inner + spacing * 16.0;
        float drift = t * 0.0022; // very slow outward ripple

        float px = 1.0 / size.y;
        float f  = ringField(p, t);
        float fx = ringField(p + float2(px, 0), t);
        float fy = ringField(p + float2(0, px), t);
        float gradLen = max(length(float2(fx - f, fy - f)), 1e-5); // field units per point

        float phase = (f - inner - drift) / spacing;
        float distPts = abs(fract(phase + 0.5) - 0.5) * spacing / gradLen;
        float line = 1.0 - smoothstep(0.2, 0.95, distPts); // ≈0.7 pt stroke

        float ringT = saturate((f - inner) / (outer - inner));
        float band = smoothstep(inner - 0.01, inner + 0.02, f) * (1.0 - smoothstep(outer - 0.05, outer + 0.01, f));
        float alpha = mix(0.15, 0.085, ringT) * band * contours;

        half3 stroke = mix(lavender, half3(1.0), 0.25h);
        col = mix(col, stroke, half(line * alpha));
    }

    // Fine duotone grain — static, pixel-locked.
    if (grain > 0.001) {
        float n = hash21(floor(position * scale / 0.75) + 0.5);
        float darkMask = step(n, 0.39);
        float lightMask = step(0.61, n);
        col = mix(col, half3(0.0), half(darkMask * 0.11 * grain));
        col = mix(col, half3(1.0), half(lightMask * 0.085 * grain));
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
