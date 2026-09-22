shader_type spatial;
// Portals (242) as swirling vortices with screen-space distortion; invisible portals (381) = faint heat haze.
// MultiMesh: INSTANCE_CUSTOM.x = phase, .y = EE rotation (0..3) / 4.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 col_a : source_color = vec3(0.35, 0.8, 1.0);
uniform vec3 col_b : source_color = vec3(0.1, 0.25, 0.9);
uniform float invisible = 0.0;
uniform float intensity = 1.0;
uniform float pulse = 0.0;

varying float v_ph;
varying float v_rot;

void vertex() {
	v_ph = INSTANCE_CUSTOM.x * 6.2832;
	v_rot = INSTANCE_CUSTOM.y * 6.2832;
}

void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv) * 2.0;
	if (r > 1.0) discard;
	float a = atan(uv.y, uv.x);
	float t = TIME * 1.2 + v_ph;
	float turb = sin(a * 5.0 + r * 9.0 - t * 2.3) * 0.25 + sin(a * 11.0 - r * 17.0 + t * 3.1) * 0.12;
	float swirl = a + 3.2 / (r + 0.25) - t * 1.6 + turb;
	float arms = 0.5 + 0.5 * sin(swirl * 3.0);
	arms = pow(arms, 2.2) * (0.75 + 0.25 * sin(r * 20.0 - t * 4.0));
	float fine = 0.5 + 0.5 * sin(swirl * 7.0 + r * 12.0);
	float body = smoothstep(1.0, 0.55, r);
	float ring = exp(-pow((r - 0.82) * 10.0, 2.0));
	float core = exp(-r * r * 14.0);
	float eye = smoothstep(0.08, 0.3, r);

	// distortion: pull the background into the spiral
	vec2 tang = normalize(vec2(-uv.y, uv.x) + 1e-5);
	float dist_amt = (1.0 - r) * (0.022 + pulse * 0.03) * (invisible > 0.5 ? 0.45 : 1.0);
	vec2 suv = SCREEN_UV + (tang * 0.8 - normalize(uv + 1e-5) * 0.6) * dist_amt * (0.6 + 0.4 * sin(t * 2.0));
	vec3 bg = textureLod(screen_tex, suv, 1.5 * (1.0 - r)).rgb;

	vec3 col;
	float alpha;
	if (invisible > 0.5) {
		col = bg + col_a * ring * 0.04;
		alpha = smoothstep(1.0, 0.6, r);
	} else {
		vec3 swirl_col = mix(col_b, col_a, arms) * (0.35 + 0.9 * arms + 0.25 * fine);
		vec3 inner = mix(swirl_col, vec3(0.02, 0.03, 0.08), (1.0 - eye) * 0.9);
		col = mix(bg * 0.6, inner, body * 0.85);
		col += col_a * ring * 1.6 + vec3(0.8, 0.95, 1.0) * core * 0.25 * eye;
		col *= intensity * (1.0 + pulse * 2.0);
		alpha = smoothstep(1.0, 0.85, r);
	}
	ALBEDO = col;
	ALPHA = alpha;
}
