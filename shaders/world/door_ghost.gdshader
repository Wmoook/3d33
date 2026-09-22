shader_type spatial;
// Passable key door / gate: faint translucent shell + bright key-coloured outline and drifting sparkles.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

#include "res://shaders/world/door_common.gdshaderinc"

varying vec3 w_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = vec2(wp.x, -wp.y);
	float z = min(door_height(p), 0.25);
	VERTEX.z = z - MODEL_MATRIX[3].z;
	w_pos = vec3(wp.xy, z);
}

void fragment() {
	vec2 p = vec2(w_pos.x, -w_pos.y);
	float sf = door_sd(p);
	if (sf < -0.07 || w_pos.z < -0.5 || mask_mode) discard;
	float t = TIME + time_offset;
	float outline = 1.0 - smoothstep(0.0, 0.07, abs(sf - 0.03));
	float plates = cobbles(p * 0.75 + fbm2(p * 0.2) * 0.8);
	float seam = 1.0 - smoothstep(0.02, 0.12, plates);
	float spark = step(0.992, hash12(floor(p * 6.0) + floor(t * 3.0)));
	float pulse = 0.6 + 0.4 * sin(t * 3.0);
	ALBEDO = key_color * (outline * 1.6 * pulse + seam * 0.25 + 0.05 + spark * 1.5);
}
