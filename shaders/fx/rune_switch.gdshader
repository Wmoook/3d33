shader_type spatial;
// Purple switch 113: a round carved rune medallion with a lever bar. Off = cool dark stone with a faint
// violet rune; on = the lever swings across and the rune ring burns purple. Dark outer rim for readability.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform vec3 on_color : source_color = vec3(0.78, 0.32, 1.0);
uniform float on_amount = 0.0;    // 0 off .. 1 on (animated)
uniform float flash = 0.0;
uniform float hc = 0.0;
uniform float phase = 0.0;

void vertex() {
	VERTEX *= 1.0 + hc * 0.35;
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, -2.0);
	float r = length(p);
	if (r > 1.0) discard;
	float a = atan(p.y, p.x);
	float on = on_amount;
	float t = TIME;
	// stone disc, top lit
	vec3 stone = mix(vec3(0.26, 0.24, 0.3), vec3(0.44, 0.42, 0.48), 0.5 + 0.5 * p.y);
	// rune ring: groove + 8 carved ticks, a travelling glow when on
	float ring = exp(-pow((r - 0.66) / 0.06, 2.0));
	float ticks = step(0.8, cos(a * 8.0 + phase)) * exp(-pow((r - 0.8) / 0.06, 2.0));
	float spin = 0.5 + 0.5 * sin(a * 3.0 - t * 3.0);
	float rune = ring * (0.6 + 0.4 * mix(1.0, spin, on)) + ticks;
	float glow = mix(0.28, 1.6 + 0.3 * sin(t * 4.0), on) + flash * 2.5;
	vec3 col = stone;
	col = mix(col, on_color * glow * (1.0 + hc * 0.5), clamp(rune, 0.0, 1.0));
	// lever: dark-outlined bar from the hub, swings from upper-left (off) to upper-right (on), glowing knob
	float ang = mix(2.25, 0.9, on);
	vec2 dir = vec2(cos(ang), sin(ang));
	float bar = seg(p, vec2(0.0), dir * 0.5);
	float knob = length(p - dir * 0.52);
	col = mix(col, vec3(0.05, 0.04, 0.06), smoothstep(0.13, 0.1, bar));
	col = mix(col, mix(vec3(0.62, 0.58, 0.66), on_color * 2.2, on) + flash, smoothstep(0.075, 0.05, bar));
	col = mix(col, vec3(0.05, 0.04, 0.06), smoothstep(0.2, 0.17, knob));
	col = mix(col, mix(vec3(0.78, 0.74, 0.82), on_color * 3.0, on) + flash, smoothstep(0.14, 0.11, knob));
	col = mix(col, vec3(0.08, 0.06, 0.1), smoothstep(0.17, 0.14, r));
	col = mix(col, on_color * (0.4 + on * 2.0), smoothstep(0.1, 0.07, r));
	// dark rim
	col = mix(col, vec3(0.03, 0.02, 0.04), smoothstep(0.86, 0.9, r));
	ALBEDO = col;
}
