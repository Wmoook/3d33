shader_type spatial;
// Faint spray rainbow over a waterfall's plunge pool (FxVeil): an additive spectral arc that breathes with
// the mist. UV (0,0) top-left; the arc is centred at the bottom middle of the quad.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float intensity = 0.35;

vec3 spectrum(float x) {
	float h = (1.0 - x) * 0.78;   // red outside -> violet inside
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 1.0 - UV.y) * vec2(2.0, 1.0);
	float r = length(p);
	float band = (r - 0.62) / 0.26;            // 0 inner (violet) .. 1 outer (red)
	if (band < 0.0 || band > 1.0) discard;
	float soft = sin(band * 3.14159);
	float feet = smoothstep(0.0, 0.35, p.y);  // fades into the spray at its feet
	float breathe = 0.75 + 0.25 * sin(TIME * 0.6) * sin(TIME * 0.23 + 1.0);
	ALBEDO = spectrum(band) * soft * feet * intensity * breathe;
}
