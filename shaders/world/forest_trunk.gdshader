shader_type spatial;
// WorldForest trunks (MultiMesh of WorldForest's tapered, root-flared trunk mesh). Round read under the dim
// canopy: painted cylindrical key/shadow (sun from the upper left), deep vertical bark furrows (photoscan bark,
// stretched), moss on the shaded side and the root flare, and far trunks that dissolve into the haze at their
// rims (soft silhouettes). Clipped to the hollow mask, faded by the region's vis.
// INSTANCE_CUSTOM: rgb = painted colour (linear), a = haze amount 0..1. UV.y = 0 at the base .. 1 at the top.
render_mode cull_back;

#include "res://shaders/world/pbr_detail.gdshaderinc"
#include "res://shaders/world/forest_mask.gdshaderinc"

uniform vec3 haze_col : source_color = vec3(0.1, 0.2, 0.17);
uniform vec3 moss_col : source_color = vec3(0.16, 0.3, 0.08);
uniform vec3 key_dir = vec3(-0.65, 0.35, 0.68);   // painted light direction (world)
uniform float shade = 0.85;
uniform vec3 fog_near : source_color = vec3(0.035, 0.07, 0.04);
uniform vec3 fog_far : source_color = vec3(0.09, 0.22, 0.18);
uniform float canopy_y = -40.0;   // above this (world y) trunks vanish into the canopy darkness

varying vec3 v_wp;
varying vec3 v_wn;
varying vec4 v_c;
varying float v_t;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_c = INSTANCE_CUSTOM;
	v_t = UV.y;
}

void fragment() {
	if (!forest_visible(v_wp, CAMERA_POSITION_WORLD)) {
		discard;
	}
	float haze = v_c.a;
	float ang = atan(v_wn.z, v_wn.x);
	// bark: stretched vertically so it reads as long furrows
	vec2 uv = vec2(ang * 0.32 + v_c.r * 7.0 + v_c.g * 3.0, -v_wp.y * 0.28);
	vec4 m = texture(pbr_tex, vec3(uv, float(PBR_BARK)));
	vec3 tn = pbr_unpack_n(m);
	float lum = m.r * 2.0;
	float furrow = smoothstep(0.45, 0.15, m.g);                     // deep cracks between the bark plates
	// cylindrical key / shadow + a dark core line on the shadow side
	vec3 vd = normalize(CAMERA_POSITION_WORLD - v_wp);
	float key = dot(v_wn, normalize(key_dir)) * 0.5 + 0.5;
	float facing = clamp(dot(v_wn, vd), 0.0, 1.0);
	float rim = 1.0 - facing;                                      // silhouette edge
	vec3 base = v_c.rgb * mix(0.6, 1.2, clamp(lum * 0.6, 0.0, 1.0)) * (1.0 - furrow * 0.55);
	// moss: shaded side + the root flare, broken up by the moss scan
	float mn = texture(pbr_tex, vec3(uv * vec2(1.0, 2.5) + 3.1, float(PBR_MOSS))).r * 2.0;
	float moss = clamp((1.0 - key) * 1.3 - 0.35 + (1.0 - smoothstep(0.0, 0.12, v_t)) * 0.6, 0.0, 1.0) * smoothstep(0.7, 1.1, mn);
	base = mix(base, moss_col * mix(0.7, 1.2, mn * 0.5), moss * (1.0 - haze));
	vec3 col = base * shade * mix(0.35, 1.2, key * key) * mix(1.0, 0.55, rim * rim);
	// far trunks: flatter, hazier, rims dissolve into the haze (no razor edges)
	// depth fog (dark green near -> blue-green glow far) + soft rims that dissolve with depth
	float fz = smoothstep(-2.5, -55.0, v_wp.z);
	float fog = clamp(max(haze, fz * 1.05) + rim * rim * fz * 0.9, 0.0, 0.97);
	col = mix(col, mix(fog_near, fog_far, fz), fog);
	// tops disappear up into the canopy darkness
	float dark = smoothstep(canopy_y - 1.0, canopy_y + 3.0 + 0.1 * -v_wp.z, v_wp.y);
	col *= 1.0 - dark * 0.92;
	ALBEDO = col * mix(0.15, 1.0, vis);
	EMISSION = mix(fog_near, fog_far, fz) * fog * 0.35 * (1.0 - dark) * vis + shade_floor(ALBEDO);
	NORMAL_MAP = vec3(tn.xy * 0.7 * (1.0 - fog) + 0.5, 1.0);
	ROUGHNESS = 0.88;
	SPECULAR = 0.2;
	AO = mix(0.5, 1.0, m.g) * mix(1.0, 0.7, 1.0 - smoothstep(0.0, 0.08, v_t));
}
