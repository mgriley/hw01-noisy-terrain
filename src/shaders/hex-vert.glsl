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
	
float random1( vec2 p , vec2 seed) {
  return fract(sin(dot(p + seed, vec2(127.1, 311.7))) * 43758.5453);
}

float random1( vec3 p , vec3 seed) {
  return fract(sin(dot(p + seed, vec3(987.654, 123.456, 531.975))) * 85734.3545);
}

vec2 random2( vec2 p , vec2 seed) {
  return fract(sin(vec2(dot(p + seed, vec2(311.7, 127.1)), dot(p + seed, vec2(269.5, 183.3)))) * 85734.3545);
}

float height_for_pt(vec2 pt) {
  float hex_radius = 5.0;
  vec2 hex_center = hexagon_center(pt, 5.0);
  //vec2 hex_center = vec2(0.0, 0.0);
  float d = sdf_hexagon(pt - hex_center, hex_radius);  
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

void main()
{
  fs_Pos = vs_Pos.xyz;
	//fs_Sine = (sin((vs_Pos.x + u_PlanePos.x) * 3.14159 * 0.1) + cos((vs_Pos.z + u_PlanePos.y) * 3.14159 * 0.1));

  vec4 world_pos = u_Model * vs_Pos;
  float d = height_for_pt(world_pos.xz);
  world_pos.y = d;

	vec3 col = vec3(1.0) - sign(d) * vec3(0.7, 0.2, 0.2);
  col /= 2.0;
	col *= 1.0 - exp(-4.0 * abs(d));
	fs_Col = vec4(col, 1.0);
  //fs_Col = vec4(0.5, 0.5, 0.0, 1.0);
  //fs_Col = mix(vec4(0.0), vec4(0.5, 0.0, 0.0, 1.0), pow(-d / hex_radius, 0.5));

  vec3 normal = compute_normal(world_pos.xz);
  fs_Nor = vec4(normal, 0.0);
  //fs_Col = vec4(1.0, 0.0, 0.0, 1.0);

  gl_Position = u_ViewProj * world_pos;
}
