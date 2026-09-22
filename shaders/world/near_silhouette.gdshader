shader_type spatial;
// Near-camera foreground silhouettes (z +3..+6) as soft procedural cards: hanging roots (with side
// strands), icicles, chains. Dark, soft-edged (reads as out of focus), faded out around the focus
// (the ball) so they never cover the gameplay near the player. INSTANCE_CUSTOM.r = shape (0/1/2),
// .g = random seed. UV.y = 0 at the top (anchor), 1 at the tip.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded, fog_disabled;

uniform vec3 focus = vec3(0.0);
uniform float clear_radius = 6.0;
uniform float fade_width = 4.0;
uniform float opacity = 0.9;
uniform float softness = 0.35;

varying vec3 w_pos;
varying vec3 v_col;
varying vec2 v_shape;

float h11(float x) { return fract(sin(x * 127.1) * 43758.5453); }
float n1(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h11(i), h11(i + 1.0), f); }

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR.rgb;
	v_shape = INSTANCE_CUSTOM.rg;
}

float strand(vec2 uv, float cx, float w0, float wig, float seed, float len) {
	float x = cx + (n1(uv.y * 3.0 + seed * 10.0) - 0.5) * wig * uv.y;
	float w = w0 * (1.0 - uv.y / len) ;
	float d = abs(uv.x - x) - w;
	return (1.0 - smoothstep(-softness * 0.1, softness * 0.12, d)) * step(uv.y, len);
}

void fragment() {
	vec2 uv = UV;
	float seed = v_shape.g * 100.0;
	float a = 0.0;
	if (v_shape.r < 0.5) {
		a = strand(uv, 0.5, 0.16, 0.25, seed, 1.0);
		a = max(a, strand(uv, 0.42, 0.06, 0.5, seed + 3.0, 0.7 + 0.25 * h11(seed)));
		a = max(a, strand(uv, 0.6, 0.05, 0.5, seed + 7.0, 0.55 + 0.3 * h11(seed + 1.0)));
	} else if (v_shape.r < 1.5) {
		float w = 0.3 * pow(1.0 - uv.y, 1.3);
		a = 1.0 - smoothstep(-0.02, softness * 0.1, abs(uv.x - 0.5) - w);
	} else {
		float link = abs(fract(uv.y * 10.0) - 0.5);
		float ring = abs(length(vec2((uv.x - 0.5) * 8.0, (link) * 2.0)) - 0.6);
		a = (1.0 - smoothstep(0.1, 0.25 + softness * 0.3, ring)) * step(abs(uv.x - 0.5), 0.2);
	}
	float d = length(w_pos.xy - focus.xy);
	ALBEDO = v_col;
	ALPHA = a * opacity * smoothstep(clear_radius, clear_radius + fade_width, d);
}
