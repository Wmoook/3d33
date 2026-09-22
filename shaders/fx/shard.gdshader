shader_type spatial;
// Death shatter shards: hot glossy gold fragments that cool as they fly.
render_mode blend_mix, cull_disabled;

uniform vec3 base : source_color = vec3(1.0, 0.76, 0.14);

void fragment() {
	float heat = COLOR.a;
	ALBEDO = base * COLOR.rgb;
	METALLIC = 0.3;
	ROUGHNESS = 0.25;
	CLEARCOAT = 1.0;
	EMISSION = mix(vec3(1.0, 0.3, 0.02), vec3(1.0, 0.7, 0.25), heat) * heat * heat * 1.6;
}
