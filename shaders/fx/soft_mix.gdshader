shader_type spatial;
// Alpha-blended soft particle puff (daylight mist / spray / dust that must not blow out to white the way
// additive sprites do over a bright sky). Colour + alpha from the process material's ramp.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float opacity = 1.0;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float m = exp(-r * r * 3.0) * (1.0 - smoothstep(0.75, 1.0, r));
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * m * opacity;
}
