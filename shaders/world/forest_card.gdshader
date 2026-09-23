shader_type spatial;
// WorldForest hanging foliage: leaf-cluster cards (atlas as WorldFoliage's) and vine strands hanging from
// the canopy into the hollow, fading into the forest haze with depth. Clipped to the hollow mask.
// INSTANCE_CUSTOM: rgb = colour (linear), a = atlas cell (int, 0-3; 4 = vine strand) + haze (fract).
render_mode cull_disabled, depth_draw_opaque, alpha_to_coverage;

#include "res://shaders/world/forest_mask.gdshaderinc"

uniform sampler2D leaf_albedo : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 haze_col : source_color = vec3(0.1, 0.2, 0.17);

varying vec3 v_wp;
varying vec4 v_c;

void vertex() {
	vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sw = sin(TIME * 0.9 + c.x * 0.7 + c.z) * 0.04 * (0.5 - UV.y);
	VERTEX.x += sw;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_c = INSTANCE_CUSTOM;
}

void fragment() {
	if (vis < 0.01 || !forest_visible(v_wp, CAMERA_POSITION_WORLD)) {
		discard;
	}
	float cell = floor(v_c.a);
	float haze = fract(v_c.a);
	float cov;
	float lum;
	if (cell > 3.5) {
		// vine: a thin wavy strand with a few leaflets
		float x = UV.x - 0.5 - sin(UV.y * 14.0 + v_c.r * 30.0) * 0.12;
		float strand = 1.0 - smoothstep(0.05, 0.09, abs(x));
		float leaflets = step(0.6, fract(UV.y * 9.0 + v_c.g * 7.0)) * (1.0 - smoothstep(0.12, 0.3, abs(x)));
		cov = max(strand, leaflets) * smoothstep(1.0, 0.8, UV.y);
		lum = 0.8;
	} else {
		vec2 auv = (vec2(mod(cell, 2.0), floor(cell / 2.0)) + UV) * 0.5;
		vec4 al = texture(leaf_albedo, auv);
		cov = al.a;
		lum = al.r * 2.0;
	}
	// antialiased cut-out (MSAA alpha-to-coverage over a ~1 px fwidth band) instead of a hard discard
	ALPHA = cov;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ALPHA_ANTIALIASING_EDGE = clamp(fwidth(cov) * 0.75, 0.005, 0.25);
	vec3 col = mix(v_c.rgb * mix(0.6, 1.1, lum * 0.5), haze_col * 0.55, haze);
	ALBEDO = col * mix(0.15, 1.0, vis);
	BACKLIGHT = col * 0.4 * vis;
	ROUGHNESS = 0.7;
	SPECULAR = 0.2;
}
