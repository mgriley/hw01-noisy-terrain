#version 300 es


uniform mat4 u_Model;
uniform mat4 u_ModelInvTr;
uniform mat4 u_ViewProj;
uniform vec2 u_PlanePos; // Our location in the virtual world displayed by the plane
uniform float u_Time;

in vec4 vs_Pos;
in vec4 vs_Nor;
in vec4 vs_Col;

out vec3 fs_Pos;
out vec4 fs_Nor;
out vec4 fs_Col;

const float pi = 3.141519;
const float hex_radius = 2.0;
const float norm_hex_start = 0.1;

struct StageState {
  vec2 pos;
  float height;
  vec3 normal;
  vec3 color;
  float norm_hex_dist;
};

float random1( vec2 p , vec2 seed) {
  return fract(sin(dot(p + seed, vec2(127.1, 311.7))) * 43758.5453);
}

float random1( vec3 p , vec3 seed) {
  return fract(sin(dot(p + seed, vec3(987.654, 123.456, 531.975))) * 85734.3545);
}

vec2 random2( vec2 p , vec2 seed) {
  return fract(sin(vec2(dot(p + seed, vec2(311.7, 127.1)), dot(p + seed, vec2(269.5, 183.3)))) * 85734.3545);
}

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
    // this gives decent noise, too
    /*
    vec2 corner = scale * corners[i];
    float corner_h = random1(corner, seed);
    vec2 delta = corner - p;
    float weight = 1.0 - smoothstep(0.0, scale, length(delta));
    sum += weight * corner_h;
    */

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

float some_noise(vec2 p, vec2 seed) {
  float noise = surflet_noise(p, seed);
  return 10.0 * (noise - 0.5) * 2.0;
}

float fbm_noise(vec2 p, vec2 seed) {
  // Note: using surflet_noise makes this slowww
  float sum = 0.0;
  float persistence = 0.5;
  for (int i = 0; i < 2; ++i) {
    float amp = pow(persistence, float(i));
    float freq = pow(2.0, float(i));
    sum += surflet_noise(p * freq, seed) * amp;
  }
  return sum;
}

// signed distance to a regular pentagon
// Rotates the geometry such that the comparison from a point to a polygon
// segment compares the point to a horizontal oriented side of the polygon
// Source: https://www.shadertoy.com/view/MtKcWW
float sdf_hexagon(vec2 p, float r) {
	int N = 6;
	float an = 6.2831853/float(N);
	float he = r*tan(0.5*an);
	
	// rotate to first sector
	//p = -p.yx; // if you want the corner to be up
	float bn = an*floor((atan(p.y,p.x)+0.5*an)/an);
	vec2  cs = vec2(cos(bn),sin(bn));
	p = mat2(cs.x,-cs.y,cs.y,cs.x)*p;

	// side of polygon
	return length(p-vec2(r,clamp(p.y,-he,he)))*sign(p.x-r);
}

vec2 hexagon_center(vec2 world_pos, float r) {
	mat2 hex_to_world = 2.0 * r * mat2(1, 0, 0.5, sqrt(3.0)/2.0);
	mat2 world_to_hex = inverse(hex_to_world);
	vec2 hex_pos = world_to_hex * world_pos;
  vec2 base_pos = floor(hex_pos);
  
  vec2 out_pos = vec2(0.0, 0.0);
  float closest_len = pow(r, 100.0);
  vec2 points[4] = vec2[4](
    base_pos,
    base_pos+vec2(1.0, 0.0),
    base_pos+vec2(0.0, 1.0),
    base_pos+vec2(1.0, 1.0));
  for (int i = 0; i < 4; ++i) {
    vec2 delta = world_pos - hex_to_world * points[i];
    float dist2 = dot(delta, delta);
    if (dist2 < closest_len) {
      closest_len = dist2;
      out_pos = points[i];
    }
  }
  return hex_to_world * out_pos;  
}

float height_for_pt_fail(vec2 pt) {
  float h_noise = surflet_noise(0.75 * pt, vec2(6.5, 92.1));
  //float h_noise = fbm_noise(1.0 * pt, vec2(6.5, 92.1));
  h_noise = (h_noise - 0.5) * 2.0;
  float d = 10.0 * h_noise;

  return d;
}

float tile_height(vec2 pt, inout vec3 color, inout float norm_hex_dist) {
  vec2 hex_center = hexagon_center(pt, hex_radius);
  float hex_dist = -sdf_hexagon(pt - hex_center, hex_radius);  
  float d = hex_dist;
  float norm_d = d / hex_radius;
  float max_height = 12.0;
  float h = 0.0;
  float norm_gap = norm_hex_start;
  float inclusion_noise = surflet_noise(hex_center * 5.0, vec2(4.8, 91.0));
  float tile_noise = surflet_noise(hex_center * 5.0, vec2(1.0, 78.0));
  if (norm_d >= norm_gap && inclusion_noise > 0.7) {
    float step_weight = smoothstep(norm_gap, 2.0 * norm_gap, norm_d);
    h = max_height * step_weight * tile_noise;
  }
  vec3 outer_color = vec3(1.0);
  vec3 inner_color = vec3(0.11, 0.12, 0.13);
  vec3 base_color = mix(outer_color, inner_color,
    smoothstep(norm_gap, 2.0 * norm_gap, norm_d));
  //float tree_band = 
  //  (1.0 - pow(smoothstep(0.0, 1.0, sin(3.0*2.0*pi*norm_d)), 0.5));
  float tree_band = 1.0;
  color = tree_band * base_color;
  norm_hex_dist = norm_d;
  return h;
}

float height_for_pt(vec2 pt) {
  vec3 color;
  float hex_d;
  return tile_height(pt, color, hex_d);
}

vec3 to_terrain_pt(vec2 pt) {
  // the pt must be given in xz coords
  return vec3(pt.x, height_for_pt(pt), pt.y);
}

vec3 compute_normal(vec2 plane_pt) {
  vec3 pt_a = to_terrain_pt(plane_pt);
  float delta = 0.001;
  vec3 pt_b = to_terrain_pt(plane_pt + delta * vec2(1.0, 0.0));
  vec3 pt_c = to_terrain_pt(plane_pt + delta * vec2(0.0, 1.0));
  vec3 span_x = pt_b - pt_a;
  vec3 span_z = pt_c - pt_a;
  vec3 normal = -cross(span_x, span_z);
  normal = normalize(normal);
  return normal;
}

void apply_tiles(inout StageState state) {
  vec3 tile_color;
  float norm_hex_dist;
  float d = tile_height(state.pos, tile_color, norm_hex_dist);  

  state.height = d;
  state.normal = compute_normal(state.pos);
  state.color = tile_color;
  state.norm_hex_dist = norm_hex_dist;
}

void apply_desert(inout StageState state) {
  float height_noise = surflet_noise(state.pos, vec2(90.0, 12.0));
  //float adhesion_height =
  //  pow(norm_
  // also mix based on depth, like the fog! (then done, jesus)
  // perturb the amount that it's mixed by, perhaps, so it shimmers
  float height = 5.0 * height_noise;
  float col_noise = surflet_noise(
    vec2(state.pos.x, state.pos.y * 40.0), vec2(87.0, 4.0));
  vec3 hill_col = mix(
    vec3(0.98, 0.99, 1.0), vec3(0.31, 0.64, 0.89), col_noise);
  if (height > state.height) {
    state.height = height;
    state.color = hill_col;
  }
}

void main()
{
  fs_Pos = vs_Pos.xyz;
  vec4 world_pos = u_Model * vs_Pos;

  StageState state = StageState(
    world_pos.xz + u_PlanePos,
    0.0, vec3(0.0, 1.0, 0.0), vec3(0.0), 0.0);
  apply_tiles(state);
  apply_desert(state);

  world_pos.y = state.height;
  fs_Nor = vec4(state.normal, 0.0);
  fs_Col = vec4(state.color, 1.0);

  gl_Position = u_ViewProj * world_pos;
}
