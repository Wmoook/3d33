shader_type spatial;
// Fish silhouette (MultiMesh), body along +x; tail wiggle travels down the body.
// INSTANCE_CUSTOM: x = phase, y = swim effort (0..1).
render_mode cull_disabled, diffuse_burley;

void vertex() {
	float k = clamp(0.25 - VERTEX.x, 0.0, 0.6);
	float eff = 0.4 + INSTANCE_CUSTOM.y * 1.2;
	VERTEX.y += sin(TIME * (7.0 + eff * 6.0) + INSTANCE_CUSTOM.x - VERTEX.x * 7.0) * 0.07 * k * eff;
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = vec3(0.03, 0.08, 0.12);
	ROUGHNESS = 0.3;
	SPECULAR = 0.7;
	EMISSION = vec3(0.08, 0.25, 0.4) * (0.35 + fres * 0.8);
}
