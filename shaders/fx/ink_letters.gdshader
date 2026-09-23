shader_type spatial;
// Illuminated lettering (FV Winners' Scroll + ΣX logo inlays): crown tiles (5) = gold leaf, red key tiles
// (6) = vermilion ink, drawn flat IN the parchment/stone. The 1-texel-per-tile mask is sampled bilinearly
// and thresholded, so pixel letters become smooth brush strokes. Gold catches a slow travelling glint;
// touched letters flare (flares[] = recent touches, same format as the key gems).
// mask: R = gold, G = vermilion. The quad covers `rect` (tile space, y down).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec4 rect = vec4(350.0, 0.0, 48.0, 72.0);   // x, y, w, h in tiles (with a 1-tile border)
uniform vec3 gold : source_color = vec3(0.82, 0.58, 0.19);
uniform vec3 gold_dark : source_color = vec3(0.36, 0.24, 0.09);
uniform vec3 vermilion : source_color = vec3(0.4, 0.07, 0.05);
uniform float glint_speed = 0.05;
uniform vec4 flares[4];
uniform vec4 flares_b[4];

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

float flare_at(vec2 w) {
	float f = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 a = flares[i];
		vec4 b = flares_b[i];
		if (a.w > 0.0) f += exp(-distance(w, a.xy) * 1.2) * exp(-a.z * 1.5) * a.w;
		if (b.w > 0.0) f += exp(-distance(w, b.xy) * 1.2) * exp(-b.z * 1.5) * b.w;
	}
	return clamp(f, 0.0, 1.5);
}

void fragment() {
	vec2 tp = vec2(v_w.x, -v_w.y);                    // tile space, y down
	vec2 uv = (tp - rect.xy) / rect.zw;
	// organic stroke edge: a little noise on the sample position
	vec2 jit = (vec2(vnoise(tp * 3.1), vnoise(tp * 3.1 + 17.0)) - 0.5) * 0.18 / rect.zw;
	vec2 m = texture(mask, uv + jit).rg;
	float g = smoothstep(0.32, 0.5, m.r);
	float v = smoothstep(0.32, 0.5, m.g);
	float cov = max(g, v);
	if (cov < 0.01) discard;
	float fl = flare_at(v_w.xy);
	// burnished gold leaf: darker in the recessed middle, bright along the stroke edge, a slow
	// view-dependent sheen (screen-space band) sweeping across; fine crackle in the leaf
	float crackle = step(0.82, vnoise(tp * 16.0)) * 0.25;
	float inner_g = smoothstep(0.55, 0.95, m.r);                 // 1 deep inside the stroke
	float rim_g = (1.0 - inner_g) * g;                           // bright burnished edge band
	float sheen_x = SCREEN_UV.x * 1.3 + SCREEN_UV.y * 0.6 - TIME * glint_speed;
	float sheen = exp(-pow((fract(sheen_x) - 0.5) / 0.08, 2.0));
	vec3 gc = mix(gold * 0.9, gold_dark, inner_g * 0.55) * (0.9 + 0.2 * vnoise(tp * 5.0) - crackle);
	gc += gold * rim_g * 0.35 + vec3(1.0, 0.9, 0.7) * sheen * (0.25 + rim_g * 0.6);
	// oxblood / cinnabar ink: matte, pooled darker at the stroke edges, slight fibre variation
	float edge_v = 1.0 - smoothstep(0.5, 0.85, m.g);
	vec3 vc = vermilion * (0.85 + 0.25 * vnoise(tp * 4.0 + 3.0));
	vc = mix(vc, vermilion * 0.42, edge_v * 0.85);
	vec3 c = g >= v ? gc : vc;
	c *= 1.0 + fl * 1.6;
	c += (g >= v ? gold : vec3(0.9, 0.3, 0.15)) * fl * 0.5;
	// sit IN the parchment: a touch of the parchment tone mixed in keeps saturation antique
	c = mix(c, vec3(dot(c, vec3(0.33))) * vec3(1.05, 0.95, 0.8), g >= v ? 0.06 : 0.18);
	ALBEDO = c;
	ALPHA = cov;
}
