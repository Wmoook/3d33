shader_type spatial;
// Forgotten Veil portals (242) as voxel-style magic rifts: a stepped ring of 8 carved stone blocks with
// glowing gold rune inlays (pixel-quantised so it fits the blocky world), holding a swirling energy vortex
// (polar noise spiral, deep indigo -> pair hue -> white-hot centre) that distorts what's behind it, with
// tiny motes spiralling in. A dark outline keeps it readable on sky and on dark stone. Portal pairs share a
// hue. The ball near it speeds the swirl up and flares it; flares[] = recent teleports through here.
// Invisible portals (381, invisible = 1): only a faint shimmer.
// MultiMesh: INSTANCE_CUSTOM.x = phase, .y = pair hue (0..1).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float invisible = 0.0;
uniform float intensity = 1.0;
uniform float pulse = 0.0;
uniform vec3 ball_pos = vec3(-1000.0);
uniform vec4 flares[4];    // xy = world pos, z = age (s), w = strength
uniform float hc = 0.0;

varying float v_ph;
varying float v_hue;
varying vec3 v_o;

vec3 hue3(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_ph = INSTANCE_CUSTOM.x * 6.2832;
	v_hue = INSTANCE_CUSTOM.y;
	v_o = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	float t = TIME + v_ph;
	float bd = distance(v_o.xy, ball_pos.xy);
	float near = smoothstep(3.5, 0.8, bd);
	float ev = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 f = flares[i];
		if (f.w <= 0.0) continue;
		float d = distance(v_o.xy, f.xy);
		ev += exp(-d * d * 2.0) * exp(-f.z * 1.8) * f.w;
	}
	float excite = clamp(near * 0.7 + ev * 1.5 + pulse, 0.0, 2.0);
	vec3 pair = hue3(v_hue);
	if (invisible > 0.5) {
		float r = length(p);
		if (r > 0.9) discard;
		vec2 n = vec2(sin(p.y * 9.0 + t * 2.0), cos(p.x * 8.0 - t * 1.7)) * 0.004;
		ALBEDO = textureLod(screen_tex, SCREEN_UV + n * (1.0 - r), 0.0).rgb;
		ALPHA = smoothstep(0.9, 0.4, r) * 0.9;
	} else {
		// voxel ring: quantise to a 12x12 block grid, stepped "rounded square" metric
		vec2 q = (floor(p * 6.0) + 0.5) / 6.0;
		float m = max(abs(q.x), abs(q.y)) * 0.55 + length(q) * 0.45;
		if (m > 0.97) discard;
		float core_r = 0.6;
		float ring = step(core_r, m);
		float outline = step(0.9, m);                          // dark outer outline row
		float inner_edge = step(core_r, m) * (1.0 - step(core_r + 0.1, m));
		float ang = atan(q.y, q.x);
		float seg = floor((ang + 3.14159) / 6.28318 * 8.0);     // 8 carved blocks
		float segf = fract((ang + 3.14159) / 6.28318 * 8.0);
		float mortar = step(segf, 0.07) + step(0.93, segf);
		// stone blocks: per-block tone, top-lit
		float tone = 0.3 + 0.12 * hash12(vec2(seg, 3.0)) + 0.1 * q.y;
		vec3 stone = vec3(tone * 0.95, tone * 0.93, tone);
		stone *= 1.0 - mortar * 0.55;
		// gold rune inlay: a short glowing bar in the middle of each block, brighter when excited
		float rune = step(0.72, m) * (1.0 - step(0.82, m)) * step(0.35, segf) * (1.0 - step(0.65, segf));
		float glow_k = 0.6 + 0.4 * sin(t * 1.6 + seg) + excite * 1.2;
		vec3 gold = vec3(1.0, 0.76, 0.3);
		stone = mix(stone, gold * (0.9 + glow_k), rune);
		stone = mix(stone, pair * (0.6 + excite), inner_edge * 0.6);   // hue-lit lip of the rift
		stone = mix(stone, vec3(0.02, 0.02, 0.03), outline);
		// vortex core
		float r = length(p) / (core_r * 1.02);
		float a = atan(p.y, p.x);
		float spin = t * (0.8 + excite * 2.5);
		float sw = a + 2.6 / (r + 0.18) - spin;
		float arms = 0.5 + 0.5 * sin(sw * 3.0 + vnoise(vec2(a * 2.0, r * 4.0 - t)) * 2.0);
		float fine = vnoise(vec2(sw * 2.0, r * 6.0 - t * 2.0));
		vec3 deep = vec3(0.1, 0.04, 0.3);
		vec3 mid = mix(vec3(0.45, 0.15, 0.85), pair, 0.6);
		vec3 core_c = mix(deep, mid, smoothstep(0.1, 0.9, arms * (1.0 - r * 0.6)));
		core_c += pair * fine * 0.35 * (1.0 - r);
		core_c = mix(core_c, vec3(1.0, 0.97, 0.92), exp(-r * r * 9.0) * (0.85 + excite * 0.3));
		// motes spiralling in
		float motes = 0.0;
		for (int k = 0; k < 6; k++) {
			float fk = float(k);
			float life = fract(t * 0.35 + fk / 6.0);
			float rr = (1.0 - life) * 0.95;
			float aa = fk * 1.047 + life * 5.0 + spin * 0.3;
			vec2 mp = vec2(cos(aa), sin(aa)) * rr * core_r;
			motes += exp(-dot(p - mp, p - mp) * 700.0) * (1.0 - life * 0.5);
		}
		core_c += (pair * 0.5 + 0.5) * motes * 1.5;
		// the world behind bends into the rift
		vec2 tang = normalize(vec2(-p.y, p.x) + 1e-5);
		vec3 bg = textureLod(screen_tex, SCREEN_UV + tang * (1.0 - r) * 0.012 * (1.0 + excite), 1.0).rgb;
		float body = smoothstep(1.0, 0.75, r);
		core_c = mix(bg * 0.5, core_c, body * 0.92 + 0.08);
		core_c *= intensity * (1.0 + excite * 0.5 + hc * 0.3);
		ALBEDO = mix(core_c, stone, ring);
		ALPHA = 1.0;
	}
}
