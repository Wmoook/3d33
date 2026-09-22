shader_type spatial;
// Dense "art pixel" action blocks (keys 6/7/8, crowns 5): small embedded stones whose base colour is the
// exact EE minimap colour, so zoomed out they are the painting's dither. A faint slow ember shows they are
// interactive; they brighten near the ball and FLARE in their key hue when touched (flares[] ring buffer).
// MultiMesh: INSTANCE_CUSTOM.x = random phase.
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.172, 0.102, 0.102);
uniform vec3 glow_color : source_color = vec3(1.0, 0.18, 0.12);
uniform float ember = 0.015;
uniform float active = 0.0;       // colour currently active (doors open) -> slightly livelier embers
uniform float glint_rate = 0.0;   // crowns: rare golden glints
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
		f += (core * 1.2 + ring * 0.45) * fl.w;
	}
	return clamp(f, 0.0, 1.3);
}

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	v_ph = INSTANCE_CUSTOM.x;
	float ph = v_ph * 40.0;
	// lumpy pebble silhouette
	float bump = sin(VERTEX.x * 9.0 + ph) * sin(VERTEX.y * 7.0 - ph * 0.7) * 0.07 + sin(VERTEX.z * 11.0 + ph * 1.3) * 0.03;
	VERTEX += NORMAL * bump;
	v_flare = flare_at(o.xy);
	v_near = smoothstep(2.6, 0.4, distance(o.xy, ball_pos.xy));
	VERTEX *= 1.0 + v_flare * 0.12;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float breathe = 0.55 + 0.45 * sin(TIME * (0.6 + active * 2.2) + v_ph * 6.2832);
	ALBEDO = base_color;
	ROUGHNESS = 0.38;
	SPECULAR = 0.55;
	CLEARCOAT = 0.35;
	// self-lit at a fraction of the minimap colour so the painting survives in unlit caves
	vec3 e = base_color * 0.22 + glow_color * ember * breathe * (1.0 + active * 1.8) * (0.4 + fres);
	e += glow_color * v_near * 0.05 * (0.5 + fres);
	// rare glints (crowns): a short bright sparkle per instance
	float g = pow(max(sin(TIME * 0.35 + v_ph * 97.0), 0.0), 400.0) * glint_rate;
	float spot = pow(max(dot(NORMAL, normalize(vec3(-0.4, 0.6, 0.7))), 0.0), 40.0);
	e += mix(glow_color, vec3(1.0), 0.3) * g * spot * 6.0;
	e += mix(glow_color, vec3(1.0), 0.12) * v_flare * 1.8;
	EMISSION = e;
}
