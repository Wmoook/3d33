shader_type spatial;
// Speed boost strip (114-117) behind the chevrons: fast additive speed lines rushing in the boost
// direction plus a soft core glow. UV.x runs along the boost direction (0..1 over length_tiles), UV.y across.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(0.35, 0.95, 1.0);
uniform float intensity = 0.9;
uniform float length_tiles = 10.0;
uniform float surge = 0.0;
uniform float hc = 0.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	float x = UV.x * length_tiles;
	float y = UV.y;
	float lines = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float ly = 0.18 + 0.64 * hash(fi * 7.1 + 0.3);
		float sp = 7.0 + hash(fi * 3.3 + 0.7) * 6.0;
		float ph = fract((x - TIME * sp) / 3.2 + hash(fi + 0.1));
		float dash = smoothstep(0.0, 0.08, ph) * (1.0 - smoothstep(0.08, 0.7, ph));
		lines += dash * exp(-pow((y - ly) / 0.035, 2.0));
	}
	float edge = smoothstep(0.0, 0.4, x) * smoothstep(0.0, 0.4, length_tiles - x);
	float core = exp(-pow((y - 0.5) / 0.28, 2.0)) * 0.18;
	ALBEDO = color * (lines + core) * intensity * edge * (1.0 + surge * 2.5) * (1.0 + hc * 0.5);
}
