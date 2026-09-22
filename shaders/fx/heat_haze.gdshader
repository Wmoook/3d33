shader_type spatial;
// Heat distortion above fires: refracts the screen with rising noise, masked to a soft column.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.006;

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
	float v = 1.0 - UV.y;
	float edge = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x) * smoothstep(0.0, 0.15, v) * smoothstep(1.0, 0.5, v);
	vec2 p = UV * vec2(6.0, 4.0) - vec2(0.0, TIME * 2.2);
	vec2 off = vec2(vnoise(p) - 0.5, vnoise(p + 11.3) - 0.5) * strength * edge;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	ALPHA = edge;
}
