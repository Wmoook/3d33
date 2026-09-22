shader_type spatial;
// Spinning coin (100 gold / 101 blue): polished metal with an embossed star + rim ridge (procedural normal map).
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 metal_color : source_color = vec3(1.0, 0.72, 0.18);
uniform vec3 glow_color : source_color = vec3(1.0, 0.6, 0.1);
uniform float glow = 0.6;

float star(vec2 p) {
	// 5-point star SDF (iq)
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-k1.x, k1.y);
	float rf = 0.45;
	float r = 0.2;
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0, 1);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float height(vec2 uv) {
	vec2 p = (uv - 0.5) * 2.0;
	float r = length(p);
	float rim = smoothstep(0.72, 0.8, r) * (1.0 - smoothstep(0.86, 0.9, r)) ;
	float s = 1.0 - smoothstep(-0.02, 0.03, star(p * vec2(1.0, -1.0) * 1.05));
	float dots = 0.0;
	return rim * 1.0 + s * 0.8;
}

void fragment() {
	bool is_rim = UV.y > 1.5;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	if (!is_rim) {
		float e = 0.004;
		float h0 = height(UV);
		float hx = height(UV + vec2(e, 0.0));
		float hy = height(UV + vec2(0.0, e));
		vec3 nm = normalize(vec3((h0 - hx) * 0.018 / e, (h0 - hy) * 0.018 / e, 1.0));
		NORMAL_MAP = nm * 0.5 + 0.5;
		ALBEDO = metal_color * (0.8 + 0.2 * h0);
		ROUGHNESS = mix(0.32, 0.12, h0);
	} else {
		float grooves = 0.5 + 0.5 * sin(UV.x * 6.2832 * 60.0);
		ALBEDO = metal_color * (0.75 + grooves * 0.2);
		ROUGHNESS = 0.3;
	}
	METALLIC = 1.0;
	EMISSION = glow_color * (glow * 0.35 + fres * glow * 1.4) + metal_color * 0.12;
}
