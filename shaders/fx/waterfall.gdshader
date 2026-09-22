shader_type spatial;
// Falling water sheet over a waterfall column (FxVeil). Streaky foam rushing down, translucent blue body,
// white churn toward the bottom. UV.x = across the column (0..1), UV.y = world tile y (down) for scrolling,
// COLOR.r = 0 at the lip .. 1 at the plunge. The ball keeps a clear disc so it never hides behind water.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 body : source_color = vec3(0.36, 0.62, 0.95);
uniform vec3 foam : source_color = vec3(0.95, 0.98, 1.0);
uniform float speed = 7.0;
uniform float opacity = 0.62;
uniform vec3 ball_pos = vec3(-1000.0);

varying vec3 v_w;
varying float v_k;

void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_k = COLOR.r;
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

void fragment() {
	float x = UV.x;
	float wy = -v_w.y;   // tile y (down)
	float t = TIME;
	// streaks: stretched noise scrolling down at two speeds
	float s1 = vnoise(vec2(v_w.x * 5.0, (wy - t * speed) * 0.35));
	float s2 = vnoise(vec2(v_w.x * 11.0 + 3.1, (wy - t * speed * 1.4) * 0.6));
	float s3 = vnoise(vec2(v_w.x * 2.3 + 7.7, (wy - t * speed * 0.7) * 0.18));
	float streak = smoothstep(0.45, 0.95, s1 * 0.55 + s2 * 0.3 + s3 * 0.35);
	float edge = smoothstep(0.0, 0.18, x) * smoothstep(0.0, 0.18, 1.0 - x);
	// ragged edges
	float rag = vnoise(vec2(v_w.x * 3.0, (wy - t * speed) * 0.5));
	edge *= smoothstep(0.15, 0.45, edge + rag * 0.35);
	float churn = smoothstep(0.55, 1.0, v_k);
	float lip = 1.0 - smoothstep(0.0, 0.06, v_k);
	vec3 c = mix(body, foam, clamp(streak * 0.85 + churn * 0.55 + lip * 0.4, 0.0, 1.0));
	c *= 0.92 + 0.12 * s2;
	float a = opacity * edge * (0.55 + streak * 0.45 + churn * 0.3);
	float bd = distance(v_w.xy, ball_pos.xy);
	a *= mix(0.12, 1.0, smoothstep(0.55, 1.3, bd));
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
