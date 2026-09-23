shader_type spatial;
// Summit shrine pillar of light (FxShrine): a soft additive column rising from the prize into the sky,
// brightest at its foot and fading with height, with slow rising shimmer bands. UV.y = 0 at the top.
// burst (0..1) sends a bright surge up the column (the crowning).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.93, 0.75);
uniform float intensity = 0.5;
uniform float burst = 0.0;
uniform float burst_h = 0.0;   // 0..1 height reached by the surge

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float h = clamp(1.0 - UV.y, 0.0, 1.0);                  // 0 at the foot .. 1 at the top
	float fade = pow(1.0 - h, 1.6) * smoothstep(0.015, 0.05, h);   // opens above the crown so it never washes it out
	float shaft = exp(-x * x * 5.0);
	float core = exp(-x * x * 45.0);
	float bands = 0.75 + 0.25 * sin(h * 60.0 - TIME * 2.2) * sin(h * 23.0 - TIME * 1.1 + x * 3.0);
	float surge = burst * exp(-pow((h - burst_h) / 0.06, 2.0)) * shaft * 3.0;
	float c = (shaft * 0.45 + core * 0.7) * fade * bands;
	ALBEDO = color * (c * intensity * (1.0 + burst * 1.5) + surge);
}
