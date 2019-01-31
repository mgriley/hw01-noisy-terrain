#version 300 es


uniform mat4 u_Model;
uniform mat4 u_ModelInvTr;
uniform mat4 u_ViewProj;
uniform vec2 u_PlanePos; // Our location in the virtual world displayed by the plane

in vec4 vs_Pos;
in vec4 vs_Nor;
in vec4 vs_Col;

out vec3 fs_Pos;
out vec4 fs_Nor;
out vec4 fs_Col;

out float fs_Sine;

const float pi = 3.141519;
const float hex_radius = 2.0;


const int NoneStage = 0;
const int TileStage = 1;
const int DesertStage = 2;

struct StageState {
  int active_stage;
  vec2 pos;
  float height;
  vec3 normal;
  vec3 color;
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

float height_for_pt(vec2 pt) {
  vec2 hex_center = hexagon_center(pt, hex_radius);
  float hex_dist = -sdf_hexagon(pt - hex_center, hex_radius);  
  float d = hex_dist;
  float norm_d = d / hex_radius;
  float max_height = 10.0;
  float tile_noise = surflet_noise(hex_center * 5.0, vec2(1.0, 78.0));
  bool is_tile = norm_d >= 0.1 && tile_noise > 0.6;
  if (is_tile) {
    d = max_height * tile_noise;
  } else {
    d = 0.0;
  }
  //float tile_height = max_height * tile_noise;
  //d = tile_height * smoothstep(0.0, 1.0, norm_d);

  //float erosion = random1(pt, vec2(12.0, 30.0));
  //erosion *= exp(-100.0 * norm_d);
  //d -= erosion * max_height;

  // erode the tile more heavily around edges
  //float erosion_weight = max_height * exp(-10.0 * hex_dist / hex_radius); 
  float erosion_weight = 0.5 * exp(-1.0 * hex_dist / hex_radius);
  float erosion = erosion_weight * surflet_noise(pt * 15.0, vec2(12.0, 31.0));
  //d = max(d - erosion, 0.0);

  // texture
  /*
  if (is_tile) {
    vec2 center_delta = pt - hex_center;
    float angle = atan(center_delta.y / center_delta.x);
    float val = sin(10.0 * angle);
    vec3 color = vec3(0.0);
    int height_band = int(floor(d)) % 2;
    if (val > 0.0 && height_band == 0) {
      color = vec3(0.75);
    }
    fs_Col = vec4(color, 1.0);
  } else {
    fs_Col = vec4(0.0, 0.0, 0.5, 1.0);
  }
  */

  return d;
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
  float d = height_for_pt(state.pos);  

  state.height = d;
  state.normal = compute_normal(state.pos);
  state.active_stage = TileStage;

  vec3 col = vec3(1.0) - sign(d) * vec3(0.7, 0.2, 0.2);
  col /= 2.0;
	col *= 1.0 - exp(-4.0 * abs(d));
  state.color = col;
  //fs_Col = mix(vec4(1.0, 1.0, 1.0, 1.0), vec4(0.0, 0.0, 0.0, 1.0), 2.0*d-1.0);
  //fs_Col *= 1.0 - exp(-1.0 * abs(d));
  //fs_Col = vec4(0.5, 0.5, 0.0, 1.0);
  //fs_Col = mix(vec4(0.0), vec4(0.5, 0.0, 0.0, 1.0), pow(-d / hex_radius, 0.5));
}

void apply_desert(inout StageState state) {
}

void main()
{
	//fs_Sine = (sin((vs_Pos.x + u_PlanePos.x) * 3.14159 * 0.1) + cos((vs_Pos.z + u_PlanePos.y) * 3.14159 * 0.1));

  fs_Pos = vs_Pos.xyz;

  vec4 world_pos = u_Model * vs_Pos;

  StageState state = StageState(NoneStage,
    world_pos.xz + u_PlanePos,
    0.0, vec3(0.0, 1.0, 0.0), vec3(0.0));
  apply_tiles(state);
  apply_desert(state);

  world_pos.y = state.height;
  fs_Nor = vec4(state.normal, 0.0);
  fs_Col = vec4(state.color, 1.0);

  gl_Position = u_ViewProj * world_pos;
}
