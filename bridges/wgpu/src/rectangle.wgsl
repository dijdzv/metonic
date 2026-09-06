struct Uniforms {
  rect: vec4f,
  viewport: vec2f,
  enabled: f32,
  pad: f32,
};

@group(0) @binding(0) var<uniform> uniforms: Uniforms;

@vertex
fn vs(@builtin(vertex_index) index: u32) -> @builtin(position) vec4f {
  var points = array<vec2f, 6>(
    vec2f(0.0, 0.0), vec2f(1.0, 0.0), vec2f(0.0, 1.0),
    vec2f(0.0, 1.0), vec2f(1.0, 0.0), vec2f(1.0, 1.0),
  );
  let pixel = uniforms.rect.xy + points[index] * uniforms.rect.zw;
  let clip = vec2f(
    pixel.x / uniforms.viewport.x * 2.0 - 1.0,
    1.0 - pixel.y / uniforms.viewport.y * 2.0,
  );
  return vec4f(clip, 0.0, 1.0);
}

@fragment
fn fs() -> @location(0) vec4f {
  return select(
    vec4f(0.08, 0.65, 0.68, 1.0),
    vec4f(0.95, 0.38, 0.10, 1.0),
    uniforms.enabled > 0.5,
  );
}
