shader_type spatial;
// Gilded trim on the ΣX logo letters (FV): the crown tiles (5) that outline the painted letters become a
// narrow bevelled gold-leaf band on the stone letter's front edge. Lit metal (sheen comes from the sun and
// the view), subtle leaf variation, touch flares (flares[] = recent crown touches, world xy / age / strength).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 gold : source_color = vec3(0.86, 0.63, 0.26);
uniform vec4 flares[4];

varying vec3 v_w;

void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float leaf = 0.9 + 0.12 * hash12(floor(v_w.xy * 9.0));
	float fl = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 f = flares[i];
		if (f.w > 0.0) fl += exp(-distance(v_w.xy, f.xy) * 1.2) * exp(-f.z * 1.5) * f.w;
	}
	// pure metal went nearly black (the sky environment gives it little to reflect): keep it a bright
	// burnished gold with a travelling view-dependent sheen so it reads as gilding in daylight
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float sheen = exp(-pow(fract((v_w.x + v_w.y) * 0.05 - TIME * 0.04) - 0.5, 2.0) / 0.004);
	ALBEDO = gold * leaf;
	METALLIC = 0.65;
	ROUGHNESS = 0.32;
	SPECULAR = 0.8;
	EMISSION = gold * leaf * (0.22 + fres * 0.35 + sheen * 0.45) + gold * clamp(fl, 0.0, 1.5) * 1.6;
}
