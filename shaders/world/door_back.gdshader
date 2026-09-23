shader_type spatial;
// What lies BEHIND an open art key door (the terrain discards those tiles while the key is active): the
// cave back wall, recessed ~2.8 units behind the gameplay plane. Lit rock tinted by the door's colour,
// layered relief with ledges and drips, and ambient occlusion from the doorway rim, so the opening reads
// as a real hollow with depth, not a flat void.
render_mode cull_back;

#include "res://shaders/world/door_common.gdshaderinc"

uniform float back_z = -2.8;
// the painting's background colour per tile (terrain bgcol, dilated): the cave / room wall that was
// painted behind the door, so the hollow matches its surroundings
uniform sampler2D bgcol_tex : source_color, filter_linear, repeat_disable;
varying vec3 w_pos;

float rockh(vec2 p) {
	float a = fbm3(p * 0.35);
	float b = cobbles(p * 0.9 + fbm2(p * 0.25) * 1.2);
	float strata = sin(p.y * 1.7 + fbm2(p * 0.15) * 3.0) * 0.5 + 0.5;
	return a * 0.55 + b * 0.3 + strata * 0.15;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = vec2(wp.x, -wp.y);
	float h = rockh(p);
	VERTEX.z = back_z + h * 0.6 - MODEL_MATRIX[3].z;
	w_pos = vec3(wp.xy, back_z + h * 0.6);
}

void fragment() {
	vec2 p = vec2(w_pos.x, -w_pos.y);
	float sf = door_sd(p);
	if (sf < -0.35 || mask_mode || foreign_door(p)) discard;
	float e = 0.05;
	float hx = rockh(p + vec2(e, 0.0)) - rockh(p - vec2(e, 0.0));
	float hy = rockh(p + vec2(0.0, e)) - rockh(p - vec2(0.0, e));
	vec3 gn = normalize(vec3(-hx / (2.0 * e) * 0.6, hy / (2.0 * e) * 0.6, 1.0));
	float h = rockh(p);
	// occlusion: darker right behind the doorway rim (the surrounding rock overhangs the recess),
	// brighter in the middle of large openings
	float ao = mix(0.22, 0.85, smoothstep(0.0, 4.0, sf));
	float crev = smoothstep(0.35, 0.1, h);
	vec3 bg = texture(bgcol_tex, (p + 0.5) / level_size).rgb;
	vec3 rock = mix(bg * 0.62, base_color * 0.4, 0.12);
	vec3 alb = rock * mix(0.55, 1.1, h) * (1.0 - crev * 0.45) * ao;
	// damp drip streaks running down
	float drip = smoothstep(0.75, 0.95, fbm2(vec2(p.x * 2.5, p.y * 0.25)));
	alb *= 1.0 - drip * 0.25;
	ALBEDO = alb;
	ROUGHNESS = mix(0.55, 0.9, h) - drip * 0.3;
	SPECULAR = 0.35;
	// a faint glow of the key colour lingering in the rock seams, so the hollow still belongs to the door
	EMISSION = key_color * crev * 0.025 * ao;
	NORMAL = normalize((VIEW_MATRIX * vec4(gn, 0.0)).xyz);
}
