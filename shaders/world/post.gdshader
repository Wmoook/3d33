shader_type canvas_item;
// Cinematic post on the FINAL composited 3D frame (drawn from a CanvasLayer at layer -10, so it sees
// every transparent effect and stays under the HUD): edge chromatic aberration, vignette, split tone,
// fine film grain.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float aberration = 0.0018;
uniform float vignette = 0.38;
uniform float grain = 0.018;
uniform vec3 shadow_tint = vec3(0.94, 0.98, 1.06);
uniform vec3 highlight_tint = vec3(1.04, 1.0, 0.95);

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
	c.x *= 1.2;
	col *= 1.0 - vignette * smoothstep(0.05, 0.42, dot(c, c));
	col += (rnd(uv * 1000.0 + fract(TIME) * 37.0) - 0.5) * grain * (0.3 + lum);
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
