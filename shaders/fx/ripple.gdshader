shader_type spatial;
// Pooled expanding rings (piano note ripples, switch pulses, speed-boost kicks). MultiMesh quads with
// per-instance COLOR; INSTANCE_CUSTOM.x = age 0..1 (CPU driven), y = ring count (1..3).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float intensity = 2.2;
varying float v_age;
varying float v_n;

void vertex() {
	v_age = INSTANCE_CUSTOM.x;
	v_n = INSTANCE_CUSTOM.y;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = 0.0;
	for (int i = 0; i < 3; i++) {
		if (float(i) >= v_n) break;
		float age = v_age - float(i) * 0.14;
		if (age <= 0.0) continue;
		float rr = sqrt(age) * 0.95;
		float w = 0.05 + age * 0.05;
		a += exp(-pow((r - rr) / w, 2.0)) * (1.0 - age) * (1.0 - float(i) * 0.3);
	}
	ALBEDO = COLOR.rgb * a * intensity * (1.0 - smoothstep(0.92, 1.0, r));
}
