shader_type spatial;
// Butterflies and birds (FxDayLife, MultiMesh). Wings flap by folding toward the camera (butterfly) or
// beating up/down (bird). Vertex COLOR.r = wing weight (0 body .. 1 tip), COLOR.g = pattern mask
// (1 = tinted wing field, 0 = dark vein / edge). INSTANCE_CUSTOM: x = flap phase, y = hue, z = kind
// (0 butterfly, 1 bird), w = flap amplitude (0 folded/perched .. 1).
render_mode cull_disabled, diffuse_burley, specular_disabled, shadows_disabled;

varying vec3 v_tint;
varying float v_pat;
varying float v_kind;

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void vertex() {
	float ph = INSTANCE_CUSTOM.x;
	float kind = INSTANCE_CUSTOM.z;
	float amp = INSTANCE_CUSTOM.w;
	float w = COLOR.r;
	v_kind = kind;
	v_pat = COLOR.g;
	if (kind < 0.5) {
		// butterfly: wings fold toward the viewer (x shrinks, z grows)
		float f = mix(1.0, 0.18 + 0.82 * abs(cos(ph)), amp);
		float x = VERTEX.x;
		VERTEX.x = x * f;
		VERTEX.z += abs(x) * sqrt(max(1.0 - f * f, 0.0)) * w;
		vec3 base = INSTANCE_CUSTOM.y < 0.0 ? vec3(1.0) : mix(vec3(1.0), hue(INSTANCE_CUSTOM.y), 0.85);
		v_tint = base;
	} else {
		// bird: the wing tip (COLOR.r = 1) beats from raised to lowered; perched (amp 0) it folds on the back
		float up = VERTEX.y;
		float y_fly = mix(-0.8 * up, up, 0.5 + 0.5 * sin(ph));
		float y_fold = 0.06;
		VERTEX.y = mix(up, mix(y_fold, y_fly, amp), w);
		VERTEX.x = mix(VERTEX.x, mix(-0.12, VERTEX.x, amp), w);
		v_tint = vec3(0.12, 0.12, 0.14);
	}
}

void fragment() {
	vec3 dark = vec3(0.04, 0.035, 0.03);
	vec3 c = mix(dark, v_tint, v_pat);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	if (v_kind < 0.5) {
		EMISSION = v_tint * v_pat * 0.08;   // a touch of self-light so wings read in shade
		BACKLIGHT = v_tint * v_pat * 0.4;
	}
}
