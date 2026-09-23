// WorldForest shared bits: the hard hollow mask (a fragment may only show where its camera ray crosses the
// gameplay plane inside a forest-hollow tile, so the illusion never draws over the painting's sky, halls or
// solids, whatever the parallax) and the per-region fade `vis` (0 = camera outside the forest).
uniform sampler2D hollow_tex : filter_nearest, repeat_disable;   // WorldForest.hollow_image (R8, 255 = hollow)
uniform vec2 hollow_size = vec2(400.0, 200.0);
uniform float vis = 1.0;

float forest_mask_at(vec3 wp, vec3 cam) {
	vec3 d = wp - cam;
	if (abs(d.z) < 1e-4) {
		return 0.0;
	}
	vec2 p = cam.xy + d.xy * (-cam.z / d.z);
	vec2 tc = vec2(p.x, -p.y);
	if (tc.x < -1.0 || tc.y < 0.0 || tc.x >= hollow_size.x + 1.0 || tc.y >= hollow_size.y + 1.0) {
		return 0.0;
	}
	tc = clamp(tc, vec2(0.0), hollow_size - 0.5);
	return texelFetch(hollow_tex, ivec2(floor(tc)), 0).r;
}

// The deep backstop / floor also covers stone-room tiles bordering a hollow (mask ~0.35): rays that enter a
// room at its edge and leave it sideways behind the plane must still end on dark forest, not sky.
bool forest_visible_deep(vec3 wp, vec3 cam) {
	return forest_mask_at(wp, cam) > 0.25;
}

bool forest_visible(vec3 wp, vec3 cam) {
	vec3 d = wp - cam;
	if (abs(d.z) < 1e-4) {
		return false;
	}
	vec2 p = cam.xy + d.xy * (-cam.z / d.z);
	vec2 tc = vec2(p.x, -p.y);
	// up to 1 tile past the level's left / right / bottom edge counts as the edge tile (world's margin wall
	// starts a little outside the level; its gap must show forest too)
	if (tc.x < -1.0 || tc.y < 0.0 || tc.x >= hollow_size.x + 1.0 || tc.y >= hollow_size.y + 1.0) {
		return false;
	}
	tc = clamp(tc, vec2(0.0), hollow_size - 0.5);
	return texelFetch(hollow_tex, ivec2(floor(tc)), 0).r > 0.5;
}

// Never-black guards (audit: exact (0,0,0) pixels = NaN normals / zero light): a unit normal with a fallback,
// and a small emission floor so a surface in full shadow still reads as dark shade.
vec3 safe_normal(vec3 n, vec3 fb) {
	float l = length(n);
	return (l > 1e-4 && l == l) ? n / l : fb;
}
vec3 shade_floor(vec3 albedo) {
	return max(albedo, vec3(0.0)) * 0.1;
}
