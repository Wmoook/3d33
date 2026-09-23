shader_type spatial;
// Floating-island keel (day levels): weathered rock and packed earth hanging under a floating ruin, darker and
// hazed toward the tip, with faint slowly pulsing levitation-rune cracks. Always behind the gameplay plane.
render_mode cull_disabled, shadows_disabled;

uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 rock_top : source_color = vec3(0.36, 0.3, 0.24);
uniform vec3 rock_tip : source_color = vec3(0.3, 0.28, 0.26);
uniform vec3 haze : source_color = vec3(0.62, 0.72, 0.92);
uniform vec3 rune_col : source_color = vec3(1.0, 0.78, 0.38);

varying float v_v;
varying float v_seed;
varying float v_pale;
uniform vec3 pale_stone : source_color = vec3(0.64, 0.6, 0.53);   // V-bird stubs: weathered grey-cream
varying vec3 v_wp;

float h2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5;
	float v = 0.0;
	for (int i = 0; i < 4; i++) { v += a * n2(p); p = p * 2.03 + 7.1; a *= 0.5; }
	return v;
}

void vertex() {
	v_v = COLOR.r;
	v_seed = COLOR.g;
	v_pale = COLOR.b;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_wp.xy;
	// strata bands + packed earth near the top, rockier toward the tip
	float strata = sin(p.y * 2.4 + fbm(p * 0.6) * 3.0) * 0.5 + 0.5;
	vec3 c = mix(rock_top, rock_tip, smoothstep(0.1, 0.8, v_v)) * mix(0.75, 1.1, strata) * mix(0.8, 1.1, fbm(p * 2.0));
	c = mix(c, pale_stone * mix(0.8, 1.05, strata), v_pale);
	// hazed and lighter toward the tip: the keel belongs to the backdrop, never a dark spike
	c = mix(c, haze, 0.08 + 0.45 * smoothstep(0.2, 1.0, v_v));
	// levitation rune cracks: thin glowing veins, strongest mid-keel, slow pulse
	float vein = smoothstep(0.98, 0.997, 1.0 - abs(fbm(p * vec2(0.9, 0.45) + v_seed * 17.0) * 2.0 - 1.0));
	float pulse = 0.55 + 0.45 * sin(TIME * 1.1 + v_seed * 20.0 + p.y * 0.4);
	float band = smoothstep(0.15, 0.4, v_v) * (1.0 - smoothstep(0.75, 0.95, v_v));
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	EMISSION = rune_col * vein * band * pulse * 0.4 * (1.0 - v_pale);
	vec3 dn = texture(detail_nrm, p * 0.4).xyz * 2.0 - 1.0;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(dn.xy * 0.6, 0.0, 0.0)).xyz);
}
