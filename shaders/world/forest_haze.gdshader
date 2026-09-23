shader_type spatial;
// WorldForest far card: the deep forest interior behind the hollow, a wall of dark-green haze with rows of
// distant trunk silhouettes receding into it and a low mist band over the floor. Unshaded (it IS the
// atmosphere); UV = tile-space position (x, y down), COLOR = the tile's painted bg colour (linear).
render_mode unshaded, cull_disabled, depth_draw_opaque, fog_disabled;

#include "res://shaders/world/forest_mask.gdshaderinc"

uniform vec3 deep_col : source_color = vec3(0.035, 0.07, 0.03);   // the painting's black gaps: deep shade
uniform vec3 haze_col : source_color = vec3(0.1, 0.2, 0.17);      // green-blue far forest haze
uniform vec3 mist_col : source_color = vec3(0.2, 0.3, 0.14);
uniform float time_scale = 1.0;

varying vec3 v_col;
varying vec3 v_wp;
varying vec2 v_floor;   // x = floor row (tile y of the floor top), y = ceiling row

float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

// A row of trunk silhouettes: 0..1 coverage at tile-space x, scale = trunks per tile.
float trunks(float x, float scale, float seed) {
	float c = floor(x * scale);
	float f = fract(x * scale);
	float w = mix(0.12, 0.3, h1(c + seed));
	float o = mix(0.25, 0.75, h1(c * 1.7 + seed + 3.0));
	float present = step(0.35, h1(c * 3.1 + seed + 7.0));
	return present * (1.0 - smoothstep(w * 0.7, w, abs(f - o)));
}

void vertex() {
	v_col = COLOR.rgb;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_floor = UV2;
}

void fragment() {
	if (!forest_visible(v_wp, CAMERA_POSITION_WORLD)) {
		discard;
	}
	vec2 p = UV;
	float t = TIME * time_scale;
	// height above the floor (tiles) and a 0..1 position between ceiling and floor
	float above = v_floor.x - p.y;
	float span = max(v_floor.x - v_floor.y, 1.0);
	float v = clamp(above / span, 0.0, 1.0);
	// the painted colour sets the local key: black gaps stay deepest, trunks/undergrowth lift it a little
	vec3 key = mix(deep_col, v_col * 0.55 + deep_col * 0.5, 0.5);
	vec3 col = mix(key, haze_col, 0.35 + 0.25 * (1.0 - v));
	// three rows of distant trunks, darker and sharper the nearer the row
	float t1 = trunks(p.x + 0.13 * sin(p.y * 0.3), 0.55, 1.0);
	float t2 = trunks(p.x + 3.1, 0.9, 5.0);
	float t3 = trunks(p.x + 7.7, 1.6, 9.0);
	col = mix(col, col * 0.45, t3 * 0.35);
	col = mix(col, col * 0.3, t2 * 0.55);
	col = mix(col, deep_col * 0.6, t1 * 0.75);
	// mist hugging the floor, drifting slowly
	float mist = smoothstep(1.6, 0.0, above) * (0.55 + 0.45 * sin(p.x * 0.35 + t * 0.15 + sin(p.x * 0.11) * 3.0));
	col = mix(col, mist_col, clamp(mist, 0.0, 1.0) * 0.45);
	// outside the forest the card stays as the painting's deep shade (no illusion)
	ALBEDO = mix(deep_col * 0.8, col, vis);
}
