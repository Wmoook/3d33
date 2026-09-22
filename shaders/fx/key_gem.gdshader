shader_type spatial;
// Key tiles (6/7/8) and crown tiles (5): small faceted gems floating in the (open-air) tile, saturated,
// self-lit so they read as PASSABLE pickups even in pitch-dark caves. Opaque (robust to sorting).
// Touch -> flares[] (ring buffer) makes them swell and burn bright; active key colour -> slightly dimmer.
// MultiMesh: INSTANCE_CUSTOM.x = random phase.
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 gem_color : source_color = vec3(1.0, 0.23, 0.23);
uniform float glow = 1.1;
uniform float active = 0.0;
uniform float bob = 0.05;
uniform float twinkle = 0.0;
uniform float hc = 0.0;          // high-contrast accessibility: +50% size and emission      // crowns: sparkle instead of pulse
uniform vec3 ball_pos = vec3(-1000.0);
uniform vec4 flares[4];           // xy = world pos, z = age (s), w = strength

varying float v_ph;
varying float v_flare;
varying float v_near;

float flare_at(vec2 o) {
	float f = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 fl = flares[i];
		if (fl.w <= 0.0) continue;
		float d = distance(o, fl.xy);
		float age = fl.z;
		float core = exp(-d * d * 1.2) * exp(-age * 2.2);
		float r = age * 4.5;
		float ring = exp(-(d - r) * (d - r) * 2.0) * exp(-age * 3.5) * step(0.3, d);
		f += (core * 1.2 + ring * 0.5) * fl.w;
	}
	return clamp(f, 0.0, 1.3);
}

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	v_ph = INSTANCE_CUSTOM.x * 6.2832;
	v_flare = flare_at(o.xy);
	v_near = smoothstep(2.5, 0.4, distance(o.xy, ball_pos.xy));
	float spin = TIME * 0.9 + v_ph;
	float c = cos(spin), s = sin(spin);
	VERTEX.xz = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xz;
	NORMAL.xz = mat2(vec2(c, s), vec2(-s, c)) * NORMAL.xz;
	VERTEX *= (1.0 + v_flare * 0.3 + v_near * 0.08) * (1.0 + hc * 0.5);
	VERTEX.y += sin(TIME * 1.8 + v_ph) * bob / max(length(MODEL_MATRIX[1].xyz), 0.01);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float pulse = 0.8 + 0.2 * sin(TIME * 2.2 + v_ph);
	float spark = pow(max(sin(TIME * 0.7 + v_ph * 13.0), 0.0), 30.0);
	// crowns twinkle gently: a strong spike bloomed into a white flare around the small dark gem
	float k = mix(pulse, 0.75 + spark * 0.45, twinkle) * (1.0 - active * 0.35);
	ALBEDO = gem_color * (0.35 + v_flare * 0.4);
	ROUGHNESS = 0.1;
	SPECULAR = 0.8;
	vec3 hot = mix(gem_color, vec3(1.0), 0.4);
	// touch flare stays in the key hue (a white-hot core blew out into a flare with the dark gem as a pupil)
	EMISSION = (1.0 + hc * 0.5) * gem_color * glow * k * (0.7 + fres * 0.8) + gem_color * v_near * 0.3 + mix(gem_color, hot, 0.35) * v_flare * 1.4;
}
