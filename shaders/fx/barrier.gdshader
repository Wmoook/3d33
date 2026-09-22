shader_type spatial;
// Key doors (23/24/25), key gates (26/28) and coin doors (43) as merged region slabs.
// `sdf` = signed distance to the region edge in tiles (level-sized float texture, linear filtered),
// so the whole region reads as one sculpted forcefield / ornate gate, never as a tile grid.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D sdf : filter_linear, repeat_disable;
uniform vec2 level_size = vec2(400.0, 200.0);
uniform vec3 color : source_color = vec3(0.9, 0.2, 0.35);
uniform float openness = 0.0;   // 0 = solid, 1 = passable
uniform float flash = 0.0;      // pulse on state change
uniform int style = 0;          // 0 energy door, 1 key gate, 2 gold coin gate
uniform float front_z = 0.5;

varying vec3 v_w;
varying vec3 v_n;

void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_n = NORMAL;
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
// distance to hexagon cell edges (0 at edges)
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec2 q = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
	q = abs(q);
	return 0.5 - max(dot(q, s * 0.5), q.x);
}

void fragment() {
	vec2 w = v_w.xy;
	vec2 uv = vec2(w.x, -w.y) / level_size;
	float sd = max(texture(sdf, uv).r, 0.0);
	bool side = abs(v_n.z) < 0.5;
	float t = TIME;
	// depth along side faces: 0 at front, 1 at back
	float depth_k = side ? clamp((front_z - v_w.z) / 1.3, 0.0, 1.0) : 0.0;
	if (side) {
		sd = 0.0;
	}

	float n1 = vnoise(w * 1.6 + vec2(0.0, t * 0.15));
	float n2 = vnoise(w * 4.3 - vec2(t * 0.2, 0.0));
	float dn = n1 * 0.65 + n2 * 0.35;
	float thr = openness * 1.15 - 0.05;
	float burn = 1.0 - smoothstep(0.0, 0.035, dn - thr);
	bool gone = dn < thr;

	vec3 albedo;
	vec3 emis;
	float alpha;
	float rough = 0.12;
	float metal = 0.0;

	if (style == 2) {
		// ---- coin gate membrane (the bars themselves are geometry): warm golden haze + engraved coin sigils
		vec3 gold = vec3(1.0, 0.72, 0.25);
		vec2 cell = fract(w) - 0.5;
		float ring = 1.0 - smoothstep(0.012, 0.03, abs(length(cell) - 0.22));
		float wave = pow(0.5 + 0.5 * sin(w.y * 2.2 - t * 1.8 + w.x * 0.4), 4.0);
		float rim = exp(-sd * 22.0);
		albedo = gold * 0.3;
		emis = gold * (0.06 + wave * 0.12 + ring * 0.25 + rim * 0.6);
		alpha = 0.28 + rim * 0.4 + ring * 0.2;
		rough = 0.3;
		if (side) {
			alpha = 0.0;
		}
		if (gone) {
			alpha = rim * 0.12;
			emis = gold * rim * 0.4;
			if (side) { alpha = 0.0; }
		}
		emis += vec3(1.0, 0.8, 0.35) * burn * 3.0 * step(0.01, openness) * (1.0 - step(0.999, openness));
	} else {
		// ---- energy forcefield (doors / gates) ----
		float hx = hex_edge(w * 2.4 + vec2(0.0, t * 0.05));
		float hex_line = 1.0 - smoothstep(0.015, 0.05, hx);
		float wave = pow(0.5 + 0.5 * sin(dot(w, vec2(0.55, 0.83)) * 1.3 - t * 2.2), 6.0);
		float sparkle = step(0.965, hash12(floor(w * 2.4 * vec2(1.0, 0.577)) + floor(t * 3.0)));
		float rim = exp(-sd * 28.0);
		float inner = exp(-sd * 5.0);
		float cells = hex_line * (0.25 + wave * 0.9 + sparkle * 0.6) * (0.4 + dn);
		albedo = color * (0.30 + 0.15 * dn);
		emis = color * (0.05 + dn * 0.08 + cells * 0.45 + inner * 0.18) + mix(color, vec3(1.0), 0.2) * rim * 1.2;
		alpha = clamp(0.72 + cells * 0.2 + rim * 0.3, 0.0, 1.0);
		if (side) {
			albedo = color * 0.22;
			emis = color * (0.4 * (1.0 - depth_k) + 0.05);
			alpha = 0.9 * (1.0 - depth_k * 0.6);
		}
		if (gone) {
			// opened: doors fade to a thin ghost outline; gates show a dashed outline
			float dash = (style == 1) ? step(0.45, fract((w.x + w.y) * 2.0)) : 1.0;
			float ghost = (1.0 - smoothstep(0.03, 0.09, sd)) * dash;
			alpha = ghost * ((style == 1) ? 0.55 : 0.32) + hex_line * 0.05;
			emis = mix(color, vec3(1.0), 0.3) * ghost * ((style == 1) ? 1.4 : 0.7) + color * hex_line * 0.12;
			albedo = color * 0.2;
			if (side) { alpha = 0.0; }
		}
		emis += mix(color, vec3(1.0), 0.25) * burn * 4.0 * step(0.01, openness) * (1.0 - step(0.999, openness));
	}
	emis += mix(color, vec3(1.0), 0.3) * flash * 0.6;
	ALBEDO = albedo;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.7;
	EMISSION = emis;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
