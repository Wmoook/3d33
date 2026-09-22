shader_type spatial;
// Leaf on a hanging vine (FxVines MultiMesh): pointed-oval blade with a dark rim and midrib, colour from
// INSTANCE_CUSTOM.rgb, lit and slightly translucent to the sun. The quad pivots at its stem (top edge).
render_mode cull_disabled, diffuse_burley, specular_disabled;

varying vec3 v_col;

void vertex() {
	v_col = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float w = 0.62 * (1.0 - p.y * p.y);
	if (abs(p.x) > w) discard;
	float rim = smoothstep(0.7, 1.0, abs(p.x) / max(w, 0.01));
	float rib = 1.0 - smoothstep(0.0, 0.07, abs(p.x));
	vec3 c = v_col * (0.9 + 0.2 * (1.0 - abs(p.x)));
	c = mix(c, c * 0.6, rib * 0.5);
	c = mix(c, v_col * 0.28, rim);
	ALBEDO = c;
	ROUGHNESS = 0.75;
	BACKLIGHT = v_col * 0.15;
}
