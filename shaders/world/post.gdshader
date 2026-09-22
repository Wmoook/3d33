shader_type spatial;
// Full-screen cinematic post: chromatic aberration at the edges, vignette, subtle film grain and a
// warm/cool split tone. Drawn as a screen quad, last in the transparent pass.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float aberration = 0.0025;
uniform float vignette = 0.38;
uniform float grain = 0.025;
uniform vec3 shadow_tint = vec3(0.92, 0.97, 1.08);
uniform vec3 highlight_tint = vec3(1.05, 1.0, 0.94);

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float rnd(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec2 off = c * r2 * aberration * 4.0;
	vec3 col;
	col.r = textureLod(screen_tex, uv - off, 0.0).r;
	col.g = textureLod(screen_tex, uv, 0.0).g;
	col.b = textureLod(screen_tex, uv + off, 0.0).b;
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col *= mix(shadow_tint, highlight_tint, smoothstep(0.05, 0.8, lum));
	float vig = 1.0 - vignette * smoothstep(0.08, 0.55, r2 * 1.6);
	col *= vig;
	col += (rnd(uv * 1000.0 + fract(TIME) * 37.0) - 0.5) * grain * (0.3 + lum);
	ALBEDO = max(col, vec3(0.0));
}
