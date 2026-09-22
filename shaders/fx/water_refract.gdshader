shader_type spatial;
// Lake water refraction layer over water tiles: animated ripple distortion of what's behind, depth-tinted
// absorption toward deep blue, and a light caustic sparkle. COLOR.r = depth below the local surface (tiles).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 deep : source_color = vec3(0.03, 0.12, 0.32);
uniform vec3 tint : source_color = vec3(0.72, 0.88, 1.0);
uniform float strength = 0.006;
uniform vec3 ball_pos = vec3(-1000.0);   // clear-water disc keeps the submerged ball crisp

varying float v_depth;
varying vec3 v_w;

void vertex() {
	v_depth = COLOR.r;
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = v_w.xy;
	float t = TIME;
	vec2 n = vec2(sin(w.x * 2.1 + t * 1.3) + sin(w.y * 3.3 - t * 1.7 + w.x * 0.7),
		cos(w.y * 2.6 + t * 1.1) + sin(w.x * 3.9 + w.y * 1.2 - t * 2.1)) * 0.5;
	float bd = distance(w, ball_pos.xy);
	float clear = 1.0 - smoothstep(0.55, 1.5, bd);
	float fade_top = smoothstep(0.0, 0.6, v_depth) * (1.0 - clear);
	vec2 uv = SCREEN_UV + n * strength * fade_top;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	float absorb = 1.0 - exp(-v_depth * 0.16);
	c = mix(c * mix(tint, vec3(0.9, 0.97, 1.0), clear), deep, absorb * 0.65 * (1.0 - clear * 0.92));
	ALBEDO = c;
	ALPHA = 1.0;
}
