shader_type spatial;
// God-mode halo: camera-facing additive disc with a soft corona, a crisp rotating ring of light
// and drifting sparkles. Premium take on EE's translucent aura.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color_a : source_color = vec3(1.0, 0.93, 0.62);
uniform vec3 color_b : source_color = vec3(0.55, 0.8, 1.0);
uniform float intensity = 1.0;
uniform float ball_r = 0.25; // ball radius in quad uv units (quad spans -0.5..0.5)

void vertex() {
	// billboard
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	float t = TIME;
	float corona = exp(-pow(max(r - ball_r, 0.0) * 9.0, 1.3)) * smoothstep(ball_r * 0.8, ball_r * 1.05, r);
	float rays = 0.5 + 0.5 * sin(a * 9.0 + t * 1.3) * sin(a * 5.0 - t * 0.9);
	corona *= 0.55 + 0.45 * rays;
	float ring_r = ball_r * 1.42 + sin(t * 2.0) * 0.006;
	float ring = exp(-pow(abs(r - ring_r) * 90.0, 2.0));
	float ring_mod = 0.6 + 0.4 * sin(a * 3.0 - t * 2.4);
	float ring2 = exp(-pow(abs(r - ball_r * 1.75) * 140.0, 2.0)) * (0.5 + 0.5 * sin(a * 24.0 + t * 3.0));
	float sp = 0.0;
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		float ang = hash(fi * 3.1) * 6.2832 + t * (0.3 + hash(fi) * 0.6);
		float rad = ball_r * (1.2 + 0.7 * fract(hash(fi * 7.7) + t * 0.15));
		vec2 c = vec2(cos(ang), sin(ang)) * rad;
		float tw = 0.5 + 0.5 * sin(t * 6.0 + fi * 2.0);
		sp += exp(-dot(uv - c, uv - c) * 9000.0) * tw;
	}
	vec3 col = mix(color_a, color_b, 0.5 + 0.5 * sin(a * 2.0 + t)) ;
	vec3 c = color_a * corona * 1.4 + col * ring * ring_mod * 2.2 + color_b * ring2 * 0.8 + vec3(1.0) * sp * 2.0;
	float edge_fade = 1.0 - smoothstep(0.4, 0.5, r);
	ALBEDO = c * intensity * edge_fade;
}
