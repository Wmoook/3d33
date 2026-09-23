shader_type spatial;
// Thin hanging strands (roots / moss drips under floating masses, WorldDecor FloatingVines) as soft-edged
// cards: coverage falls off smoothly across the strand's width (in screen pixels, via fwidth), so a strand
// only a few pixels wide stays stable under sub-pixel camera motion instead of crawling (hard-edged thin
// boxes aliased). Lit like the foliage props; a gentle taper to the tip.
render_mode cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform float rough = 0.8;
uniform float translucency = 0.4;

varying vec3 v_col;

void vertex() {
	v_col = COLOR.rgb;
}

void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);          // 0 at the centre line, 1 at the card edge
	float taper = mix(1.0, 0.45, UV.y);        // UV.y = 0 at the root, 1 at the tip
	float px = max(fwidth(UV.x * 2.0), 1e-4);  // card-width units per pixel
	float cov = 1.0 - smoothstep(taper - px * 2.5, taper + px * 0.8, x);
	cov *= 1.0 - smoothstep(0.85, 1.0, UV.y);  // soft tip
	if (cov < 0.01) {
		discard;
	}
	ALBEDO = v_col * (0.85 + 0.15 * (1.0 - x));
	ROUGHNESS = rough;
	SPECULAR = 0.3;
	BACKLIGHT = v_col * translucency;
	ALPHA = cov;
}
