shader_type spatial;
// Hanging vine segment (FxVines MultiMesh): a tapered ribbon quad from one verlet node to the next.
// Mesh: unit quad spanning y in [-1, 0] (top at the node, bottom at the next); INSTANCE_CUSTOM.x = width
// at the top, y = width at the bottom, z = shade variation. Lit, darker along the edges for a readable
// silhouette against the bright sky and pale stone.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform vec3 stem : source_color = vec3(0.16, 0.3, 0.07);
uniform vec3 stem_dark : source_color = vec3(0.06, 0.12, 0.03);

varying float v_shade;

void vertex() {
	float w = mix(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y, -VERTEX.y);
	VERTEX.x *= w;
	v_shade = INSTANCE_CUSTOM.z;
}

void fragment() {
	float e = abs(UV.x - 0.5) * 2.0;
	vec3 c = mix(stem, stem_dark, smoothstep(0.35, 1.0, e));
	ALBEDO = c * (0.8 + 0.4 * v_shade);
	ROUGHNESS = 0.7;
	BACKLIGHT = stem * 0.35;
}
