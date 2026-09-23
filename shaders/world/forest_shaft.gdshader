shader_type spatial;
// WorldForest sun shafts through the canopy: soft additive light beams (QuadMesh, UV.y 0 = top).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

#include "res://shaders/world/forest_mask.gdshaderinc"

uniform vec3 shaft_col : source_color = vec3(1.0, 0.9, 0.62);
uniform float strength = 0.16;

varying float v_seed;
varying vec3 v_wp;

void vertex() {
	v_seed = INSTANCE_CUSTOM.r;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (vis < 0.01 || !forest_visible(v_wp, CAMERA_POSITION_WORLD)) {
		discard;
	}
	float edge = 1.0 - smoothstep(0.15, 0.5, abs(UV.x - 0.5));
	float fall = smoothstep(0.0, 0.15, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float dust = 0.75 + 0.25 * sin(UV.y * 23.0 - TIME * 0.6 + v_seed * 40.0) * sin(UV.x * 9.0 + TIME * 0.3);
	float breathe = 0.7 + 0.3 * sin(TIME * 0.4 + v_seed * 6.28);
	ALBEDO = shaft_col * edge * fall * dust * breathe * strength * vis;
}
