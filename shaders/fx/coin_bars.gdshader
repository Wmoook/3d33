shader_type spatial;
// Coin-door gate bars (id 43): polished gold bars that retract upward into the frame when the gate opens.
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float openness = 0.0;
uniform vec3 gold : source_color = vec3(1.0, 0.74, 0.28);

varying vec3 v_w;

void vertex() {
	float k = clamp(openness, 0.0, 1.0);
	float e = k * k * (3.0 - 2.0 * k);
	VERTEX.y = 0.5 - (0.5 - VERTEX.y) * (1.0 - e);
	VERTEX.xz *= 1.0 - e * 0.6;
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float band = smoothstep(0.02, 0.0, abs(fract(v_w.y * 2.0) - 0.5) - 0.44);
	float glint = pow(max(sin(v_w.x * 0.8 + v_w.y * 0.5 - TIME * 1.6), 0.0), 24.0);
	ALBEDO = gold * (0.85 + band * 0.15);
	METALLIC = 1.0;
	ROUGHNESS = mix(0.22, 0.12, band);
	EMISSION = gold * (0.06 + fres * 0.5 + glint * 0.8);
}
