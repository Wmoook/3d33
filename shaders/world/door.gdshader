shader_type spatial;
// Key doors / key gates: sculpted masses in their minimap colour with glowing key-coloured rune seams and
// a pulsing edge light ("you need the red key"). GHOST variant (while passable): a faint translucent shell
// with a bright outline, so it clearly reads as open.
render_mode depth_draw_opaque, cull_back;

#include "res://shaders/world/door_common.gdshaderinc"

varying vec3 w_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = vec2(wp.x, -wp.y);
	float z = door_height(p);
	VERTEX.z = z - MODEL_MATRIX[3].z;
	w_pos = vec3(wp.xy, z);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

vec3 srgb2lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	vec3 wp = w_pos;
	vec2 p = vec2(wp.x, -wp.y);
	float sf = door_sd(p);
	if (sf < -0.07) discard;
	if (mask_mode) {
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
		EMISSION = vec3(1.0);
	} else {
		float e = 0.035;
		vec3 gn;
		if (sf < 0.0) {
			vec2 g = vec2(door_sd(p + vec2(e, 0.0)) - door_sd(p - vec2(e, 0.0)), door_sd(p + vec2(0.0, e)) - door_sd(p - vec2(0.0, e)));
			gn = normalize(vec3(-g.x, g.y, 0.0001));
		} else {
			float hx = door_height(p + vec2(e, 0.0)) - door_height(p - vec2(e, 0.0));
			float hy = door_height(p + vec2(0.0, e)) - door_height(p - vec2(0.0, e));
			gn = normalize(vec3(-hx / (2.0 * e), hy / (2.0 * e), 1.0));
		}
		float t = TIME + time_offset;
		// rune seams: the gaps between large carved plates glow in the key colour, pulsing
		float plates = cobbles(p * 0.75 + fbm2(p * 0.2) * 0.8);
		float seam = 1.0 - smoothstep(0.02, 0.16, plates);
		float pulse = 0.55 + 0.45 * sin(t * 2.4 - (p.x + p.y) * 0.35);
		float edge = 1.0 - smoothstep(0.0, 0.2, max(sf, 0.0));
		vec3 bc = base_color * mix(0.72, 1.08, plates) * mix(0.35, 1.0, smoothstep(-2.5, -0.2, wp.z));
		ALBEDO = bc;
		ROUGHNESS = 0.42;
		SPECULAR = 0.55;
		EMISSION = key_color * (seam * pulse * 0.55 + edge * (0.3 + 0.3 * pulse)) * smoothstep(-1.2, -0.1, wp.z);
		NORMAL = normalize((VIEW_MATRIX * vec4(gn, 0.0)).xyz);
	}
}
