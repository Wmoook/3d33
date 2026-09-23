shader_type spatial;
// CLOSED key door / key gate: opaque, solid, lit like terrain.
// - doors (channel 0): carved slabs in their key colour inside a dark bevelled stone FRAME with one crisp
//   key-coloured inlay line just inside the rim ("sealed by the red key"), faint rune seams.
// - gates (channel 1): an iron PORTCULLIS: dark iron frame and crossbars with key-coloured vertical bars,
//   so a closed gate never reads like a door (or like an open ghost).
// Emission stays low (no bloom blow-out); the colour carries the key.
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

void fragment() {
	vec3 wp = w_pos;
	vec2 p = vec2(wp.x, -wp.y);
	float sf = door_sd(p);
	if (sf < -0.07 || foreign_door(p)) discard;
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
		float front = smoothstep(-2.5, -0.2, wp.z);          // side walls darker than the face
		float frame = 1.0 - smoothstep(0.18, 0.3, sf);        // bevelled rim band
		float inlay = 1.0 - smoothstep(0.0, 0.035, abs(sf - 0.34));
		float pulse = 0.75 + 0.25 * sin(t * 1.6 - (p.x + p.y) * 0.3);
		vec3 kc = key_color;
		vec3 alb;
		vec3 emit;
		if (channel == 0) {
			float plates = cobbles(p * 0.75 + fbm2(p * 0.2) * 0.8);
			float seam = 1.0 - smoothstep(0.02, 0.12, plates);
			alb = base_color * mix(0.78, 1.08, plates) * (1.0 - seam * 0.35);
			alb = mix(alb, vec3(0.13, 0.12, 0.12) + base_color * 0.18, frame);
			emit = kc * (seam * 0.06 + inlay * 0.32 * pulse);
			ROUGHNESS = mix(0.55, 0.8, frame);
			SPECULAR = 0.4;
		} else {
			// portcullis: vertical key-coloured bars every half tile, iron crossbars every tile
			float bx = abs(fract(p.x * 2.0) - 0.5);
			float by = abs(fract(p.y) - 0.5);
			float bar = 1.0 - smoothstep(0.16, 0.22, bx);
			float xbar = 1.0 - smoothstep(0.38, 0.44, by);
			vec3 iron = vec3(0.1, 0.1, 0.11);
			alb = mix(iron * 0.6, base_color * 1.15, bar);
			alb = mix(alb, iron * 1.4, (1.0 - xbar) * (1.0 - bar * 0.5));
			alb = mix(alb, iron, frame);
			// bars stand proud of the backing plate
			gn = normalize(gn + vec3((fract(p.x * 2.0) - 0.5) * bar * 1.2, 0.0, 0.0));
			emit = kc * (bar * 0.05 + inlay * 0.28 * pulse);
			ROUGHNESS = mix(0.35, 0.7, 1.0 - bar);
			SPECULAR = 0.6;
		}
		ALBEDO = alb * mix(0.35, 1.0, front);
		EMISSION = emit * front;
		NORMAL = normalize((VIEW_MATRIX * vec4(gn, 0.0)).xyz);
	}
}
