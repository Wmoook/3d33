shader_type spatial;
// Bat silhouette (MultiMesh). Wings flap by bending the outer vertices; folded while roosting.
// INSTANCE_CUSTOM: x = flap phase (rad), y = wing openness (0 folded .. 1 flying). COLOR.r > .5 marks eyes.
render_mode cull_disabled, diffuse_burley;

varying float v_eye;

void vertex() {
	v_eye = COLOR.r;
	float ax = abs(VERTEX.x);
	float s = sign(VERTEX.x);
	float open = INSTANCE_CUSTOM.y;
	if (ax > 0.055) {
		float w = ax - 0.055;
		float fl = sin(INSTANCE_CUSTOM.x);
		VERTEX.x = s * (0.055 + w * mix(0.18, 1.0, open));
		VERTEX.y += w * (fl * 0.55 * open - (1.0 - open) * 0.6);
		VERTEX.z += w * fl * 0.8 * open;
	}
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = vec3(0.045, 0.035, 0.05);
	ROUGHNESS = 0.7;
	EMISSION = vec3(0.12, 0.1, 0.16) * (0.25 + fres) + vec3(1.0, 0.12, 0.05) * v_eye * 2.5;
}
