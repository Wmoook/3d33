shader_type spatial;
// Forgotten Veil portals (242) = "the Veil": a shimmering vertical membrane of light held in a carved
// stone ring. The membrane refracts what is behind it, carries slow iridescent interference bands and
// ripples outward when the ball comes close or passes through (flares[] = recent portal events).
// Invisible portals (381, invisible = 1): only a faint heat-shimmer, no ring.
// MultiMesh: INSTANCE_CUSTOM.x = phase.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 veil_a : source_color = vec3(0.62, 0.9, 1.0);
uniform vec3 veil_b : source_color = vec3(0.95, 0.75, 1.0);
uniform float invisible = 0.0;
uniform float intensity = 1.0;
uniform float pulse = 0.0;
uniform vec3 ball_pos = vec3(-1000.0);
uniform vec4 flares[4];    // xy = world pos, z = age (s), w = strength

varying float v_ph;
varying vec3 v_o;

void vertex() {
	v_ph = INSTANCE_CUSTOM.x * 6.2832;
	v_o = MODEL_MATRIX[3].xyz;
}

vec3 spectrum(float x) {
	return clamp(abs(fract(x + vec3(0.0, 0.33, 0.67)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	vec2 q = p * vec2(1.35, 1.0);            // tall oval membrane
	float r = length(q);
	float t = TIME + v_ph;
	// ripple sources: the ball nearby + recent passes through this portal
	float bd = distance(v_o.xy, ball_pos.xy);
	float near = smoothstep(3.0, 0.6, bd);
	float ev = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 f = flares[i];
		if (f.w <= 0.0) continue;
		float d = distance(v_o.xy, f.xy);
		ev += exp(-d * d * 2.0) * exp(-f.z * 1.6) * f.w;
	}
	float wob = (near * 0.6 + ev * 1.4 + pulse * 0.5);
	float rip = sin(r * 16.0 - t * (4.0 + wob * 6.0)) * (0.25 + wob) * smoothstep(1.0, 0.2, r);
	float sway = sin(p.y * 5.0 + t * 1.3) * 0.02 + sin(p.x * 7.0 - t * 1.7) * 0.015;
	vec2 n = normalize(q + 1e-4) * rip * 0.012 + vec2(sway, sway * 0.6);
	if (invisible > 0.5) {
		if (r > 0.95) discard;
		vec3 bg = textureLod(screen_tex, SCREEN_UV + n * 0.6, 0.0).rgb;
		float spark = pow(max(sin(p.y * 9.0 - t * 2.0 + p.x * 4.0), 0.0), 20.0) * 0.08;
		ALBEDO = bg + veil_a * spark;
		ALPHA = smoothstep(0.95, 0.5, r) * (0.8 + near * 0.2);
	} else {
		if (length(p * vec2(1.1, 0.9)) > 1.0) discard;
		float ring_r = length(p * vec2(1.1, 0.9));
		// stone ring: dark carved band with a pale bevel + a few rune notches
		float ring = smoothstep(0.78, 0.8, ring_r);
		float bevel = exp(-pow((ring_r - 0.83) / 0.03, 2.0));
		float ang = atan(p.y, p.x);
		float notch = step(0.93, cos(ang * 6.0 + 0.5)) * smoothstep(0.82, 0.86, ring_r) * (1.0 - smoothstep(0.93, 0.96, ring_r));
		vec3 bg = textureLod(screen_tex, SCREEN_UV + n, 1.0).rgb;
		// membrane: refracted background tinted by drifting iridescent bands + a bright rim of light
		float band = sin(q.y * 6.0 + sin(q.x * 3.0 + t * 0.7) * 1.5 - t * 0.9) * 0.5 + 0.5;
		vec3 irid = mix(veil_a, veil_b, band) * 0.6 + spectrum(band * 0.5 + t * 0.05 + r * 0.3) * 0.25;
		float mem = smoothstep(0.8, 0.1, r);
		float edge = exp(-pow((ring_r - 0.76) / 0.05, 2.0));
		float shimmer = 0.5 + 0.5 * sin(q.y * 30.0 + t * 3.0 + q.x * 8.0);
		vec3 m = mix(bg, bg * 0.55 + irid * (0.8 + 0.4 * shimmer), 0.55 + mem * 0.2);
		m += veil_a * (edge * 1.3 + abs(rip) * 0.5 * mem) + vec3(1.0) * ev * 0.4 * mem;
		m *= intensity * (1.0 + pulse);
		vec3 stone = mix(vec3(0.12, 0.13, 0.15), vec3(0.42, 0.44, 0.47), bevel);
		stone = mix(stone, veil_a * 1.8, notch * (0.4 + 0.6 * near + ev));
		vec3 col = mix(m, stone, ring);
		ALBEDO = col;
		ALPHA = 1.0;
	}
}
