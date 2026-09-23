// WorldVoxel's aerial haze curve, shared so other layers (detail's blocky forest) fade exactly like the voxel
// landscape. Requires vista_common.gdshaderinc. Returns the haze fraction f (mix toward
// vista_sky(normalize(wp - cam), sun_dir) by f, or ALBEDO *= 1 - f; EMISSION += sky * f for lit materials).
// Layout: the sky's aerial perspective (density 0.0011) plus a readability floor that ramps from 0.08 at the
// gameplay plane to 0.40 at 120 units back, and fades out beyond z -60 (far things keep their colour).
float voxel_haze_f(vec3 wp, vec3 cam) {
	float f = vista_fog_f(wp, cam, 0.0011, 0.0);
	float dz = -wp.z - 3.0;
	float rk = 1.0 - smoothstep(55.0, 95.0, dz);
	return max(f, mix(0.08, 0.40, smoothstep(0.0, 120.0, dz)) * rk);
}
