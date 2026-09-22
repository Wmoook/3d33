shader_type spatial;
// Cheap shadow-only proxy of the terrain height field (low vertex density, trivial fragment):
// the full-res terrain mesh doesn't cast shadows; this does.
render_mode unshaded, cull_disabled;

#include "res://shaders/world/terrain_common.gdshaderinc"

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float height_margin = 16.0;
uniform float shadow_sink = 0.06;   // push the proxy slightly behind the real surface (no acne)

varying vec2 v_p;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = vec2(wp.x, -wp.y);
	vec2 uv = (p + height_margin) / (level_size + 2.0 * height_margin);
	VERTEX.z = textureLod(height_tex, uv, 0.0).r - shadow_sink - MODEL_MATRIX[3].z;
	v_p = p;
}

void fragment() {
	vec4 s = sdf_linear(v_p);
	if (s.x < -0.07 && s.y < -0.07 && field_at(v_p).r > 0.5) {
		discard;   // open sky casts no shadow
	}
	ALBEDO = vec3(0.0);
}
