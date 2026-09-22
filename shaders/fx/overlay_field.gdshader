shader_type spatial;
// Living light over the painted terrain, one quad for the whole level (just in front of the terrain face).
// mask: R = fire (1 yellow / .6 orange), G = caustic weight, B = ice glint, A = splash stream.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D mask_lin : filter_linear, repeat_disable;
uniform sampler2D mask_near : filter_nearest, repeat_disable;
uniform vec2 level_size = vec2(400.0, 200.0);
uniform float fire_gain = 1.0;
uniform float caustic_gain = 1.0;
uniform float glint_gain = 1.0;
uniform float stream_gain = 1.0;

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
float fbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}
// organic animated caustic web (classic iterative water-caustic, tileable over TAU)
float caustic(vec2 p, float time) {
	vec2 q = mod(p * 0.9, 6.2831853) - 250.0;
	vec2 i = q;
	float c = 1.0;
	float inten = 0.005;
	for (int n = 0; n < 4; n++) {
		float t = time * (1.0 - (3.5 / float(n + 1)));
		i = q + vec2(cos(t - i.x) + sin(t + i.y), sin(t - i.y) + cos(t + i.x));
		c += 1.0 / length(vec2(q.x / (sin(i.x + t) / inten), q.y / (cos(i.y + t) / inten)));
	}
	c /= 4.0;
	c = 1.17 - pow(c, 1.4);
	return clamp(pow(abs(c), 8.0), 0.0, 3.0);
}

void fragment() {
	vec2 w = v_w.xy;
	vec2 tp = vec2(w.x, -w.y);
	vec2 uv = tp / level_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) discard;
	vec4 m = texture(mask_lin, uv);
	if (dot(m, vec4(1.0)) < 0.01) discard;
	// light stays inside the painted tiles (no bleed into the air in front of the ball)
	vec4 mh = texelFetch(mask_near, ivec2(floor(tp)), 0);
	float t = TIME;
	vec3 col = vec3(0.0);

	float fire_m = smoothstep(0.3, 0.85, m.r);
	if (fire_m > 0.0) {
		// flowing fire: noise rising upward, hotter in yellow tiles
		float n = fbm(vec2(w.x * 1.3, w.y * 0.9 - t * 1.6));
		float n2 = fbm(vec2(w.x * 3.1 + 5.0, w.y * 2.2 - t * 3.1));
		float heat = clamp(n * 0.8 + n2 * 0.5 - 0.35, 0.0, 1.0);
		float hot = max(mh.r, m.r);
		vec3 fc = mix(vec3(1.0, 0.25, 0.03), vec3(1.0, 0.75, 0.25), heat * hot);
		fc = mix(fc, vec3(1.0, 0.95, 0.8), pow(heat, 4.0) * hot);
		float flick = 0.8 + 0.2 * sin(t * 13.0 + w.x * 3.0) * sin(t * 7.3 + w.y * 2.0);
		col += fc * (0.05 + heat * 0.55) * fire_m * flick * fire_gain;
	}
	if (m.g > 0.01 && mh.g > 0.0) {
		float c = caustic(w, t * 0.5);
		// strongest on the rock just above/around the water, gentle on the water body itself
		float on_water = mh.g > 0.99 ? 0.35 : 1.0;
		col += vec3(0.45, 0.78, 1.0) * c * m.g * 0.16 * on_water * caustic_gain;
	}
	if (mh.b > 0.0) {
		// sparse twinkling glints on ice
		vec2 cell = floor(w * 3.0);
		float h = hash12(cell);
		vec2 c = (fract(w * 3.0) - 0.5) - (vec2(hash12(cell + 7.0), hash12(cell + 3.0)) - 0.5) * 0.6;
		float tw = pow(max(sin(t * (1.0 + h * 2.0) + h * 40.0), 0.0), 10.0);
		float star = exp(-dot(c, c) * 180.0) + exp(-abs(c.x) * 60.0 - abs(c.y) * 9.0) * 0.3 + exp(-abs(c.y) * 60.0 - abs(c.x) * 9.0) * 0.3;
		col += vec3(0.8, 0.92, 1.0) * star * tw * step(0.4, h) * mh.b * 3.0 * glint_gain;
		col += vec3(0.4, 0.6, 1.0) * mh.b * 0.03;
	}
	if (mh.a > 0.0) {
		// sheets of water streaking down
		float lane = floor(w.x * 5.0);
		float sp = 3.0 + hash12(vec2(lane, 1.0)) * 3.0;
		float s = fract(w.y * 0.7 + t * sp * 0.35 + hash12(vec2(lane, 5.0)));
		float streak = pow(s, 6.0) * (0.5 + 0.5 * hash12(vec2(lane, 9.0)));
		float across = 1.0 - abs(fract(w.x * 5.0) - 0.5) * 2.0;
		col += vec3(0.7, 0.9, 1.0) * (streak * pow(across, 2.0) * 1.4 + 0.05) * m.a * stream_gain;
	}
	ALBEDO = col;
}
