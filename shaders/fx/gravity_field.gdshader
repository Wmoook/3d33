shader_type spatial;
// Gravity arrows (ids 1/2/3) and dots (4) as one continuous energy-current field.
// A single quad covers the level; `field` holds per-tile masks (R=left, G=up, B=right, A=dot).
// Linear sampling gives soft merged regions; texelFetch gives exact tiles for readable chevrons.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D field_lin : filter_linear, repeat_disable;
uniform sampler2D field_near : filter_nearest, repeat_disable;
uniform vec2 level_size = vec2(400.0, 200.0);
uniform vec3 col_core : source_color = vec3(1.0, 0.86, 0.45);
uniform vec3 col_edge : source_color = vec3(0.9, 0.7, 0.4);
uniform vec3 col_dot : source_color = vec3(0.75, 0.9, 1.0);
uniform float intensity = 0.3;
uniform float flow_speed = 1.0;
uniform vec3 ball_pos = vec3(-1000.0);  // currents brighten and quicken around the ball

varying vec3 v_w;

void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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

// Flowing streak layer for direction d (world, y up). Returns brightness.
float streaks(vec2 w, vec2 d, float seed, float t) {
	vec2 n = vec2(-d.y, d.x);
	float s = dot(w, d);
	float q = dot(w, n);
	// gentle meander so it reads like wind / current rather than rails
	q += (vnoise(vec2(s * 0.35 - t * 0.6, q * 0.5) + seed) - 0.5) * 0.55;
	float acc = 0.0;
	for (int k = 0; k < 2; k++) {
		float lw = (k == 0) ? 0.19 : 0.11;
		float lane = floor(q / lw);
		float h = hash12(vec2(lane, seed + float(k) * 7.0));
		float h2 = hash12(vec2(lane * 1.7, seed + 3.0 + float(k)));
		float across = abs(fract(q / lw) - 0.5) * 2.0;
		float prof = pow(max(1.0 - across, 0.0), (k == 0) ? 5.0 : 8.0);
		float sp = (2.6 + h * 2.2) * flow_speed;
		float len = 2.2 + h2 * 2.0;   // spacing between specks along a lane
		float ph = fract((s - t * sp) / len + h * 9.0);
		// comet: pattern moves toward +s, so the bright head sits at ph -> 1 and the tail trails behind
		float comet = smoothstep(0.82, 0.97, ph) * (1.0 - smoothstep(0.97, 1.0, ph)) * step(0.72, h2);
		acc += prof * comet * ((k == 0) ? 1.0 : 0.6);
	}
	return acc;
}

// Chevron marker moving through an exact arrow tile. lc = local coords in [-0.5, 0.5] (world axes).
float chevron(vec2 lc, vec2 d, float t) {
	vec2 n = vec2(-d.y, d.x);
	float a = dot(lc, d);
	float c = dot(lc, n);
	float best = 0.0;
	for (int i = 0; i < 1; i++) {
		float off = fract(t * 0.7) - 0.5;   // travel -0.5..0.5
		float shape = abs((a - off) + abs(c) * 0.85) ;
		float line = 1.0 - smoothstep(0.035, 0.075, shape);
		float fade = smoothstep(0.5, 0.2, abs(off)) * smoothstep(0.32, 0.18, abs(c));
		best = max(best, line * fade);
	}
	return best;
}

void fragment() {
	vec2 w = v_w.xy;
	vec2 t_px = vec2(w.x, -w.y);   // tile space (y down)
	vec2 uv = t_px / level_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}
	vec4 soft = texture(field_lin, uv);
	if (dot(soft, vec4(1.0)) < 0.004) {
		discard;
	}
	vec4 hard = texelFetch(field_near, ivec2(floor(t_px)), 0);
	vec2 lc = fract(t_px) - 0.5;
	lc.y = -lc.y;
	float t = TIME;

	vec3 col = vec3(0.0);
	ivec2 ti = ivec2(floor(t_px));
	vec4 nb = texelFetch(field_near, ti + ivec2(1, 0), 0) + texelFetch(field_near, ti + ivec2(-1, 0), 0)
		+ texelFetch(field_near, ti + ivec2(0, 1), 0) + texelFetch(field_near, ti + ivec2(0, -1), 0);
	float tile_h = hash12(vec2(ti));
	vec2 dirs[3] = vec2[3](vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(1.0, 0.0));
	for (int k = 0; k < 3; k++) {
		float wsoft = soft[k];
		if (wsoft < 0.004) continue;
		float m = smoothstep(0.08, 0.7, wsoft);
		vec2 d = dirs[k];
		float st = streaks(w, d, float(k) * 13.1, t);
		float gust = vnoise(w * 0.45 - d * t * 1.1);
		float haze = 0.006 + 0.035 * gust * gust;
		// chevrons: every tile of thin arrow lines; only a sparse scatter inside big current fields
		float sparse = nb[k] >= 2.0 ? step(0.9, tile_h) : 1.0;
		float chev = chevron(lc, d, t + tile_h) * hard[k] * sparse;
		vec3 c = mix(col_edge, col_core, clamp(st, 0.0, 1.0));
		col += c * (st * (0.55 + gust * 0.6) + haze) * m ;  // per-tile chevrons are real geometry now (grav_glyph)
	}
	// zero-gravity dots: a calm hovering mote per tile + soft shimmer
	float wd = soft.a;
	if (wd > 0.004) {
		float m = smoothstep(0.08, 0.7, wd);
		vec2 tile = floor(t_px);
		float ph = hash12(tile) * 6.283;
		vec2 bob = vec2(sin(t * 0.9 + ph) * 0.06, cos(t * 1.1 + ph * 1.3) * 0.08);
		float r = length(lc - bob);
		float mote = (exp(-r * r * 320.0) * 1.3 + exp(-r * r * 60.0) * 0.12) * hard.a;
		float shimmer = 0.012 + 0.02 * vnoise(w * 2.0 + vec2(t * 0.3, -t * 0.2));
		col += col_dot * (mote * 0.3 + shimmer * m);
	}
	float near = smoothstep(3.2, 0.3, distance(w, ball_pos.xy));
	ALBEDO = col * intensity * (1.0 + near * 1.6);
}
