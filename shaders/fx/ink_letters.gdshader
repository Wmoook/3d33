shader_type spatial;
// Illuminated lettering (FV Winners' Scroll + ΣX logo inlays): crown tiles (5) = gold leaf, red key tiles
// (6) = vermilion ink, drawn flat IN the parchment/stone. The 1-texel-per-tile mask is sampled bilinearly
// and thresholded, so pixel letters become smooth brush strokes. Gold catches a slow travelling glint;
// touched letters flare (flares[] = recent touches, same format as the key gems).
// mask: R = gold, G = vermilion. The quad covers `rect` (tile space, y down).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec4 rect = vec4(350.0, 0.0, 48.0, 72.0);   // x, y, w, h in tiles (with a 1-tile border)
uniform vec3 gold : source_color = vec3(1.0, 0.72, 0.22);
uniform vec3 gold_dark : source_color = vec3(0.45, 0.28, 0.06);
uniform vec3 vermilion : source_color = vec3(0.62, 0.07, 0.04);
uniform float glint_speed = 0.12;
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
	// gold leaf: crackled leaf texture, darker burnished edges, a slow diagonal glint sweeping across
	float leaf = 0.8 + 0.25 * vnoise(tp * 6.0) - 0.15 * step(0.8, vnoise(tp * 14.0));
	float edge_g = 1.0 - smoothstep(0.5, 0.75, m.r);
	float sweep = fract((tp.x + tp.y * 0.6) * 0.035 - TIME * glint_speed);
	float glint = exp(-pow((sweep - 0.5) / 0.03, 2.0)) * 0.6;
	vec3 gc = mix(gold * leaf, gold_dark, edge_g * 0.7) + vec3(1.0, 0.95, 0.8) * glint * (1.0 - edge_g);
	// vermilion ink: matte, pooled darker at the stroke edges
	float edge_v = 1.0 - smoothstep(0.5, 0.8, m.g);
	vec3 vc = mix(vermilion * (0.9 + 0.2 * vnoise(tp * 4.0)), vermilion * 0.45, edge_v * 0.8);
	vec3 c = g >= v ? gc : vc;
	c *= 1.0 + fl * 1.8;
	c += (g >= v ? gold : vec3(1.0, 0.35, 0.2)) * fl * 0.6;
	ALBEDO = c;
	ALPHA = cov;
}
