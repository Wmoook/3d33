shader_type spatial;
// Grass blades / leaf clumps / props for MultiMesh instances. Vertex colour = gradient along the
// blade (a = sway weight), instance colour = tint, INSTANCE_CUSTOM.r = emission.
render_mode cull_disabled, depth_draw_opaque;

uniform float wind = 1.0;
uniform float translucency = 0.35;
uniform float emission_boost = 0.0;
uniform float rough = 0.7;

varying vec3 v_col;
varying float v_emit;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = COLOR.a;
	float ph = wp.x * 0.35 + wp.z * 0.5;
	float w = sin(TIME * 1.7 + ph) * 0.6 + sin(TIME * 3.1 + ph * 2.3) * 0.25 + sin(TIME * 0.45 + wp.x * 0.05) * 0.6;
	VERTEX.x += w * 0.08 * sway * wind;
	VERTEX.z += w * 0.03 * sway * wind;
	v_col = COLOR.rgb;  // vertex colour x instance colour (MultiMesh use_colors)
	v_emit = INSTANCE_CUSTOM.a;
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	BACKLIGHT = v_col * translucency;
	EMISSION = v_col * (v_emit + emission_boost);
}
