#version 300 es
precision highp float;

// The fragment shader used to render the background of the scene
// Modify this to make your background more interesting

uniform float u_Time;

in vec4 fs_Pos;

out vec4 out_Col;

vec2 random2( vec2 p , vec2 seed) {
  return fract(sin(vec2(dot(p + seed, vec2(311.7, 127.1)), dot(p + seed, vec2(269.5, 183.3)))) * 85734.3545);
}

// copied from hex-vert. minor modifications
float surflet_noise(vec2 p, vec2 seed) {
  // use the surface-lets technique
  // scale is the length of a cell in the perlin grid
  float scale = 10.0;
  vec2 base = floor(p / scale);
  vec2 corners[4] = vec2[4](
    base,
    base + vec2(1.0, 0.0),
    base + vec2(0.0, 1.0),
    base + vec2(1.0, 1.0)
  );
  float sum = 0.0;
  for (int i = 0; i < 4; ++i) {
    vec2 corner = scale * corners[i];
    vec2 corner_dir = 2.0 * random2(corner, seed) - vec2(1.0);
    vec2 delta = p - corner;
    // this is the height if we were only on a slope of
    // magnitude length(corner_dir) in the direction of corner_dir
    float sloped_height = dot(delta, corner_dir);
    float weight = 1.0 - smoothstep(0.0, scale, length(delta));
    sum += 0.25 * weight * sloped_height;
  }
  return (sum + 1.0) / 2.0;
}

void main() {
  vec2 pos = fs_Pos.xy; 
  vec3 white_col = vec3(1.0);
  vec3 grey_col = vec3(0.60, 0.65, 0.62);
  vec2 sky_pos = pos + vec2(1.0, 0.0) * u_Time / 40.0;
  vec2 seed = vec2(54.0, 31.9);
  float cloud_noise = surflet_noise(
    vec2(sky_pos.x * 100.0, sky_pos.y * 400.0), seed);
  cloud_noise = cloud_noise * pow(clamp(0.0, 1.0, pos.y), 10.0); 
  vec3 col = mix(white_col, grey_col, cloud_noise);

  out_Col = vec4(col, 1.0);
}

