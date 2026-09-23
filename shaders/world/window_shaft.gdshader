shader_type spatial;
// Soft god-rays falling from the structure windows into the rooms, ending in a warm light pool where they
// land. Additive and faint so they never wash out gameplay. UV.x across the shaft, UV.y along it (0 at the
// window); UV2.x = 1 for stained windows (the light takes a little of the glass colours).
render_mode blend_add, depth_draw_never, cull_disabled, shadows_disabled, unshaded, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.9, 0.7);
uniform float strength = 0.1;

varying float stained;

void vertex() {
	stained = UV2.x;
}

float h11(float x) {
	return fract(sin(x * 91.7) * 43758.5453);
}

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float across = 1.0 - pow(abs(x), 2.2);
	// separate rays through the lattice: a few bright bands drifting very slowly
	float rays = 0.6 + 0.4 * sin(UV.x * 18.0 + sin(UV.y * 3.0 + TIME * 0.15) * 1.2);
	float along = smoothstep(0.0, 0.1, UV.y) * (1.0 - smoothstep(0.45, 1.0, UV.y));
	// the pool: brighter, wider falloff where the shaft lands
	float pool = smoothstep(0.62, 0.9, UV.y) * (1.0 - smoothstep(0.9, 1.0, UV.y)) * (1.0 - x * x) * 1.4;
	float motes = 0.88 + 0.12 * sin(UV.y * 40.0 + TIME * 0.6 + UV.x * 9.0);
	float dust = step(0.985, h11(floor(UV.x * 30.0) + floor(UV.y * 60.0 - TIME * 2.0) * 7.0)) * along * 1.5;
	vec3 col = color;
	if (stained > 0.5) {
		col = mix(color, vec3(0.9, 0.75, 1.0) * (0.6 + 0.4 * sin(vec3(0.0, 2.1, 4.2) + UV.x * 6.0)), 0.35);
	}
	ALBEDO = col * (across * along * rays * motes + pool + dust) * strength;
}
