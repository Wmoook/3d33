shader_type spatial;
// Drifting leaf / petal particle: pointed-oval silhouette with a midrib, flutters (flips edge-on and back)
// as it falls. Colour from the process material (initial colour ramp). Alpha-scissored, lit by the sun.
render_mode cull_disabled, diffuse_burley, specular_disabled, shadows_disabled;

uniform float flutter = 5.0;

varying float v_flip;

void vertex() {
	float ph = float(INSTANCE_ID) * 1.618 + TIME * flutter * (0.7 + fract(float(INSTANCE_ID) * 0.37) * 0.6);
	v_flip = cos(ph);
	VERTEX.x *= 0.25 + 0.75 * abs(v_flip);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float w = 0.55 * (1.0 - p.y * p.y);          // pointed at both tips
	float inside = step(abs(p.x), w) * step(abs(p.y), 1.0);
	if (inside < 0.5) discard;
	float rib = 1.0 - smoothstep(0.0, 0.08, abs(p.x));
	vec3 c = COLOR.rgb * (0.85 + 0.25 * (1.0 - abs(p.x) / max(w, 0.01)));
	c = mix(c, c * 0.65, rib * 0.6);
	c *= 0.8 + 0.2 * abs(v_flip);
	ALBEDO = c;
	ROUGHNESS = 0.8;
	BACKLIGHT = COLOR.rgb * 0.5;
}
