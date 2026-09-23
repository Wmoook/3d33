shader_type spatial;
// OPEN (passable) key door / gate: almost no fill, so the scene behind shows through clearly, and a crisp
// key-coloured DASHED outline marching along the boundary (+ a soft inner band) so the doorway is still
// readable. Open gates add faint "raised portcullis" bar ticks along their top/bottom edges.
// Alpha-blended (not additive), so it never washes out over bright backgrounds.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

#include "res://shaders/world/door_common.gdshaderinc"

varying vec3 w_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = vec2(wp.x, -wp.y);
	VERTEX.z = 0.3 - MODEL_MATRIX[3].z;     // flat, just in front of the gameplay plane
	w_pos = vec3(wp.xy, 0.3);
}

void fragment() {
	vec2 p = vec2(w_pos.x, -w_pos.y);
	float sf = door_sd(p);
	if (sf < -0.06 || mask_mode || foreign_door(p)) discard;
	float t = TIME + time_offset;
	// crisp outline on the boundary, dashed (dashes march slowly around the doorway)
	float line = 1.0 - smoothstep(0.035, 0.075, abs(sf - 0.02));
	float along = p.x * 0.7 + p.y * 1.3;
	float dash = step(0.38, fract(along * 1.2 - t * 0.4));
	float band = (1.0 - smoothstep(0.0, 0.5, sf)) * 0.16;          // soft inner band hugging the edge
	float fill = 0.035;
	float ticks = 0.0;
	if (channel == 1) {
		// raised portcullis: faint bar ticks
		ticks = (1.0 - smoothstep(0.1, 0.16, abs(fract(p.x * 2.0) - 0.5))) * (1.0 - smoothstep(0.1, 0.45, sf)) * 0.35;
	}
	float a = max(line * mix(0.35, 0.95, dash), band + fill + ticks);
	ALBEDO = mix(key_color * 0.9, vec3(1.0), line * dash * 0.25);
	ALPHA = clamp(a, 0.0, 1.0);
}
