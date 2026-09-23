shader_type spatial;
// WorldForest deep layers: the opaque BACKSTOP (a huge far wall at z ~ -62: blue-green glow low, canopy
// darkness above, far trunk silhouettes) and the receding forest FLOOR (moss/leaf-litter plane stepping down
// gently with depth, fading into the fog). Unshaded atmosphere; clipped to the (dilated) hollow mask.
// COLOR.a: 0 = backstop, 1 = floor.
render_mode unshaded, cull_disabled, depth_draw_opaque, fog_disabled;

#include "res://shaders/world/forest_mask.gdshaderinc"

uniform vec3 fog_near : source_color = vec3(0.035, 0.07, 0.04);   // dark green near
uniform vec3 fog_far : source_color = vec3(0.09, 0.22, 0.18);     // blue-green glow far back
uniform vec3 canopy_dark : source_color = vec3(0.045, 0.075, 0.05);   // darkest shade stays above the black-air floor
uniform vec3 floor_col : source_color = vec3(0.07, 0.11, 0.04);
uniform float floor_y = -58.0;     // world y of the region's forest floor at the play strip
uniform float canopy_y = -40.0;    // world y of the canopy underside (tops vanish above this)

varying vec3 v_wp;
varying float v_kind;

float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h1(i.x + i.y * 57.0);
	float b = h1(i.x + 1.0 + i.y * 57.0);
	float c = h1(i.x + (i.y + 1.0) * 57.0);
	float d = h1(i.x + 1.0 + (i.y + 1.0) * 57.0);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float trunk_row(float x, float scale, float seed) {
	float c = floor(x * scale);
	float f = fract(x * scale);
	float w = mix(0.08, 0.22, h1(c + seed));
	float o = mix(0.25, 0.75, h1(c * 1.7 + seed + 3.0));
	float present = step(0.3, h1(c * 3.1 + seed + 7.0));
	return present * (1.0 - smoothstep(w * 0.5, w, abs(f - o)));
}

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_kind = COLOR.a;
}

void fragment() {
	if (!forest_visible(v_wp, CAMERA_POSITION_WORLD)) {
		discard;
	}
	vec3 col;
	if (v_kind < 0.5) {
		// backstop: glow band around the (far, perspective-lowered) floor horizon, dark canopy above
		float h = v_wp.y - floor_y * 1.0;
		float glow = exp(-max(h, 0.0) * 0.028) * smoothstep(-40.0, 0.0, h);
		col = mix(canopy_dark, fog_far, clamp(glow, 0.0, 1.0));
		// two rows of far trunk silhouettes, a touch darker than the glow, tops lost in the dark
		float t1 = trunk_row(v_wp.x * 0.25, 1.0, 11.0);
		float t2 = trunk_row(v_wp.x * 0.25 + 3.3, 1.7, 23.0);
		col = mix(col, col * 0.55, t2 * 0.6);
		col = mix(col, col * 0.4, t1 * 0.75);
		col *= 0.85 + 0.15 * vn(v_wp.xy * 0.08);
	} else {
		// floor: moss + litter noise, fog with distance
		float d = clamp((-v_wp.z - 1.9) / 58.0, 0.0, 1.0);
		float n = vn(v_wp.xz * 1.3) * 0.6 + vn(v_wp.xz * 0.3) * 0.4;
		col = floor_col * mix(0.6, 1.25, n);
		float f = smoothstep(0.0, 0.85, d);
		col = mix(col, mix(fog_near, fog_far * 0.75, f), f * 0.9);
		// low mist hugging the floor near the front
		col = mix(col, fog_far * 0.6, (1.0 - d) * 0.1 * (0.6 + 0.4 * sin(v_wp.x * 0.4 + TIME * 0.2)));
	}
	ALBEDO = mix(canopy_dark, col, 0.25 + 0.75 * vis);
}
