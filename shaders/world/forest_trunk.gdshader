shader_type spatial;
// WorldForest receding trunks (MultiMesh cylinders). Bark = the photoscan bark layer (pbr_detail), tinted by
// the painted trunk colour; trunks deeper in the forest dissolve into the dark-green haze.
// INSTANCE_CUSTOM: rgb = painted colour (linear), a = haze amount 0..1.
render_mode cull_back;

#include "res://shaders/world/pbr_detail.gdshaderinc"
#include "res://shaders/world/forest_mask.gdshaderinc"

uniform vec3 haze_col : source_color = vec3(0.1, 0.2, 0.17);
uniform vec3 moss_col : source_color = vec3(0.16, 0.3, 0.08);
uniform float shade = 0.8;   // under the closed canopy: the trunks get only filtered light

varying vec3 v_wp;
varying vec3 v_wn;
varying vec4 v_c;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_c = INSTANCE_CUSTOM;
}

void fragment() {
	if (!forest_visible(v_wp, CAMERA_POSITION_WORLD)) {
		discard;
	}
	// bark runs along the trunk: cylindrical mapping (around, up)
	float ang = atan(v_wn.z, v_wn.x);
	vec2 uv = vec2(ang * 0.25 + v_c.r * 7.0, -v_wp.y * 0.55);
	vec4 m = texture(pbr_tex, vec3(uv, float(PBR_BARK)));
	vec3 tn = pbr_unpack_n(m);
	float lum = m.r * 2.0;
	vec3 base = v_c.rgb * mix(0.55, 1.25, clamp(lum * 0.6, 0.0, 1.0));
	float haze = v_c.a;
	// moss creeping up the trunks from the floor and on the side facing the canopy light
	float moss = smoothstep(0.55, 0.85, texture(pbr_tex, vec3(uv * 0.7 + 3.1, float(PBR_MOSS))).r * 2.0 * 0.55
		+ max(-v_wn.x, 0.0) * 0.4);
	base = mix(base, moss_col * mix(0.7, 1.2, lum * 0.5), moss * 0.6 * (1.0 - haze));
	vec3 col = mix(base * shade, haze_col * 0.6, haze * 0.85);
	ALBEDO = col * mix(0.15, 1.0, vis);
	EMISSION = haze_col * haze * 0.35 * vis;
	NORMAL_MAP = vec3(tn.xy * 0.5 * (1.0 - haze) + 0.5, 1.0);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	AO = mix(0.55, 1.0, m.g);
}
