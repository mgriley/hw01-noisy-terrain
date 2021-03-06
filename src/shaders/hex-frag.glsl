#version 300 es
precision highp float;

uniform vec2 u_PlanePos; // Our location in the virtual world displayed by the plane

in vec3 fs_Pos;
in vec4 fs_Nor;
in vec4 fs_Col;

out vec4 out_Col; // This is the final output color that you will see on your
                  // screen for the pixel that is currently being processed.

void main()
{
  // lambertian shading
  vec3 light_dir = normalize(vec3(1.0, 1.0, 1.0));
  float diffuse_term = dot(light_dir, normalize(fs_Nor.xyz));
  diffuse_term = clamp(diffuse_term, 0.0, 1.0);
  float light_intensity = diffuse_term + 0.2f;
  vec4 col = vec4(light_intensity * fs_Col.rgb, fs_Col.a);

	//out_Col = col;
  //out_Col = fs_Col;

  float t = clamp(smoothstep(40.0, 50.0, length(fs_Pos)), 0.0, 1.0); // Distance fog
  out_Col = vec4(mix(col.rgb, vec3(0.77, 0.78, 0.82), t), 1.0);
}
