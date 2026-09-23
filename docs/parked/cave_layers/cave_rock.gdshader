shader_type spatial;
// WorldCaveLayers: big rock masses inside FV earth caves, seen face-on at their layer depth. World-space
// rock strata in the cave's regional tone (WorldBgSpace), a soft bevel darkening at slab edges, the light
// field from the cave's openings (warmer, brighter near them), and per-layer fog toward the cave gloom.
render_mode cull_back;

#include "res://shaders/world/bg_space.gdshaderinc"

uniform vec2 level_size = vec2(400.0, 200.0);
uniform float fog = 0.3;

varying vec3 w_pos;
varying vec3 l_pos;
varying vec3 w_n;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	l_pos = VERTEX;
	w_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = vec2(w_pos.x, -w_pos.y);
	vec3 n = normalize(w_n);
	vec3 tone = bg_space_tone(p, level_size);
	vec3 base = mix(vec3(0.17, 0.11, 0.06), tone * 3.0, 0.35);
	// strata on the faces (world space: continuous across slabs of one layer)
	vec2 q = abs(n.z) > 0.5 ? p : (abs(n.x) > 0.5 ? vec2(w_pos.z, -w_pos.y) : vec2(w_pos.x, w_pos.z));
	float sy = q.y * 1.1 + bgs_fbm(vec2(q.x * 0.1, q.y * 0.3)) * 2.2;
	float band = fract(sy);
	float layer = bgs_h(vec2(floor(sy), 3.0));
	float grain = bgs_fbm(q * vec2(1.3, 2.8));
	vec3 alb = base * mix(0.7, 1.2, layer) * mix(0.8, 1.15, grain) * mix(0.72, 1.0, smoothstep(0.0, 0.12, band));
	// slab edges: soft darkening toward the box silhouette (reads as rounded rock, no hard lines)
	vec3 e = 0.5 - abs(l_pos);
	float edge = smoothstep(0.0, 0.08, min(e.x, e.y) * 1.0);
	alb *= mix(0.7, 1.0, edge);
	// side faces are in the cave's shadow
	alb *= abs(n.z) > 0.5 ? 1.25 : 0.55;
	// lit top edges (the masses catch the light from above: a readable silhouette against the dark back)
	alb *= 1.0 + 0.5 * smoothstep(0.42, 0.5, l_pos.y) * step(0.5, abs(n.z));
	float ao = 1.0;
	vec3 emit = bg_space_light(p, level_size, 1, alb, ao);
	vec3 gloom = vec3(0.035, 0.024, 0.016);
	ALBEDO = mix(alb, gloom, fog);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
	AO = ao;
	EMISSION = emit * (1.0 - fog) + gloom * fog * 0.6 + alb * 0.04;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n + vec3(grain - 0.5, 0.0, 0.0) * 0.3), 0.0)).xyz);
}
