#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// The Sprout Lens glass. `layer` is the map already magnified by `zoom` around `center`; this
/// bends it near the rim (samples are pulled toward the centre, like the thick edge of a convex
/// lens) and shades the glass: a soft highlight up and to the left, a darker rim below right.
/// Positions are in the layer's points. Outside the lens it returns transparent.
[[ stitchable ]] half4 lens(float2 position, SwiftUI::Layer layer, float2 center, float radius,
                            float zoom) {
  float2 d = position - center;
  float r = length(d) / max(radius, 1.0);
  if (r >= 1.0) {
    return half4(0.0h);
  }

  // Refraction grows toward the rim; stronger zoom bends a little more.
  float edge = smoothstep(0.55, 1.0, r);
  float strength = 0.16 * clamp(1.0 - 1.0 / max(zoom, 1.0), 0.0, 1.0);
  half4 color = layer.sample(position - d * edge * edge * strength * 2.0);

  // Glass shading after the concept: bright toward (-0.35, -0.4) R, dark toward the edge.
  float2 lightCenter = center + float2(-0.35, -0.4) * radius;
  float g = length(position - lightCenter) / radius;
  float highlight = 0.28 * (1.0 - smoothstep(0.1, 0.6, g));
  float shade = 0.12 * smoothstep(0.6, 1.0, r);
  // A thin specular band just inside the rim, strongest at the upper left.
  float facing = clamp(dot(normalize(d + 1e-4), float2(-0.62, -0.78)), 0.0, 1.0);
  float rim = smoothstep(0.86, 0.93, r) * (1.0 - smoothstep(0.95, 1.0, r)) * facing * 0.35;

  // Colours are premultiplied, so white at this alpha is `color.a`.
  half3 rgb = color.rgb;
  rgb = mix(rgb, half3(color.a), half(highlight + rim));
  rgb = mix(rgb, half3(0.0h), half(shade));
  return half4(rgb, color.a);
}
