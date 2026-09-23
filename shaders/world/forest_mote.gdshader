shader_type spatial;
// WorldForest fireflies and drifting pollen (GPUParticles3D draw pass: a small camera-facing quad).
// COLOR from the particle process (rgb, a = life fade). custom: fireflies blink.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

#include "res://shaders/world/forest_mask.gdshaderinc"

uniform vec3 mote_col : source_color = vec3(1.0, 0.85, 0.4);
uniform float blink = 1.0;      // 1 = firefly pulse, 0 = steady pollen
uniform float strength = 1.0;

varying vec3 v_wp;
varying float v_ph;

void vertex() {
	// billboard
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_wp = MODEL_MATRIX[3].xyz;
	v_ph = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9, 78.2, 37.7))) * 43758.5);
}

void fragment() {
	if (vis < 0.01 || !forest_visible(v_wp, CAMERA_POSITION_WORLD)) {
		discard;
	}
	float r = length(UV - 0.5) * 2.0;
	float glow = exp(-r * r * 5.0);
	float pulse = mix(1.0, pow(max(sin(TIME * 1.7 + v_ph * 40.0), 0.0), 3.0), blink);
	ALBEDO = mote_col * glow * pulse * COLOR.a * strength * vis;
}
