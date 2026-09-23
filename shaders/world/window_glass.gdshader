shader_type spatial;
// Leaded glass panes in the structure windows (WorldDepth rooms). The glass is CLEAR: the real far scenery
// behind the tower (sky dome, clouds, vista islands, voxel landscape) shows through with its true
// parallax, at >= 75% transmission. Unshaded, so the sun never turns the panes into an opaque beige sheet.
// On top: a faint cool tint that varies per quarry (hand-made glass), a soft sky-reflection sheen that
// grows at grazing angles, one thin diagonal highlight streak per pane, and thin dark lead cames in a
// diamond lattice. Stained accents (UV2.x = 1) are richer coloured glass, still see-through.
// Frosted lancets (UV2.y = 1) sit behind gameplay glyphs: dimmed and softly frosted so arrows stay crisp.
// UV = tile (x, y) (unused: the lattice is world-anchored).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.86, 0.94, 1.0);
uniform float clear_alpha = 0.1;       // glass body opacity (0.1 = 90% of the view through)

varying vec2 t;
varying vec3 wpos;
varying float stained;
varying float frosted;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	t = vec2(wpos.x, -wpos.y);
	stained = UV2.x;
	frosted = UV2.y;
}

void fragment() {
	// diamond lattice (leaded quarries) + a vertical lead every tile
	vec2 q = vec2(t.x + t.y, t.x - t.y) * 1.6;
	vec2 f = abs(fract(q) - 0.5);
	float came = 1.0 - smoothstep(0.03, 0.055, min(0.5 - f.x, 0.5 - f.y));
	came = max(came, 1.0 - smoothstep(0.02, 0.045, abs(fract(t.x) - 0.5) - 0.455));
	vec2 cell = floor(q);
	float quarry = h21(cell);
	// view angle: glass reflects more of the sky when seen obliquely
	vec3 v = normalize(wpos - CAMERA_POSITION_WORLD);
	float graze = 1.0 - abs(v.z);
	float sheen = 0.04 + 0.35 * pow(graze, 2.0);
	// one thin diagonal highlight streak per 2 tiles (window light catching the glass)
	float streak = 1.0 - smoothstep(0.0, 0.05, abs(fract((t.x - t.y * 0.6) * 0.5 + 0.13) - 0.5));
	streak *= 0.5 + 0.5 * h21(floor(t * 0.5));
	vec3 c = tint * (0.92 + 0.12 * quarry);
	float a = clear_alpha + quarry * 0.05 + sheen * 0.4 + streak * 0.14;
	if (stained > 0.5) {
		float k = h21(cell + 5.0);
		vec3 sc = k < 0.25 ? vec3(0.95, 0.72, 0.25) : (k < 0.5 ? vec3(0.25, 0.7, 0.72) : (k < 0.75 ? vec3(0.75, 0.3, 0.35) : tint));
		c = sc;
		a += 0.12;
	}
	if (frosted > 0.5) {
		// behind glyphs: a soft cool frost that dims what is behind so arrows and dots stay crisp
		float fr = 0.5 + 0.5 * h21(floor(t * 11.0));
		c = mix(c, vec3(0.7, 0.76, 0.84), 0.3);
		a += 0.05 + fr * 0.03;
	}
	vec3 lead = vec3(0.06, 0.06, 0.07);
	// HDR-bright glass body: the sky seen through is > 1 before tonemapping, so a plain 0.9 tint would dim it
	ALBEDO = mix((c * 1.5) + vec3(streak * 0.5), lead, came);
	ALPHA = clamp(mix(a, 0.92, came), 0.0, 1.0);
}
