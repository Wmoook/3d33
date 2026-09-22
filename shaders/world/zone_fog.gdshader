shader_type fog;
// Spatially varying volumetric fog: per-region density/colour/emission from a low-res zone field,
// with drifting wisps. Lives in a FogVolume box covering the level's depth slab.

uniform sampler2D fog_field : filter_linear, repeat_disable;  // rgb = albedo, a = density
uniform sampler2D fog_emit : filter_linear, repeat_disable;   // rgb = emission, a = ground-mist amount
uniform vec2 level_size = vec2(400.0, 200.0);
uniform float density_scale = 1.0;
uniform float emission_scale = 1.0;

float h3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i + vec3(0, 0, 0)), h3(i + vec3(1, 0, 0)), f.x),
				mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x),
				mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fog() {
	vec3 wp = WORLD_POSITION;
	vec2 uv = vec2(wp.x, -wp.y) / level_size;
	vec4 fld = texture(fog_field, uv);
	vec4 em = texture(fog_emit, uv);
	vec3 q = wp * vec3(0.12, 0.16, 0.25) + vec3(TIME * 0.05, TIME * 0.02, TIME * 0.03);
	float wisps = vnoise(q) * 0.65 + vnoise(q * 2.3 + 4.0) * 0.35;
	// thicker towards the back of the slab: depth haze behind the gameplay plane
	// thin in front of / around the gameplay plane (keeps the playfield crisp), thick behind it
	float back = smoothstep(-0.5, -9.0, wp.z);
	float d = fld.a * mix(0.08, 1.0, back) * (0.45 + 1.1 * wisps);
	// low-lying mist pooling in cave floors (em.a)
	d += em.a * smoothstep(0.55, 0.9, wisps) * 0.6;
	DENSITY = d * density_scale;
	ALBEDO = fld.rgb;
	EMISSION = em.rgb * emission_scale * (0.5 + wisps);
}
