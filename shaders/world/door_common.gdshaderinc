// Shared door / gate field functions (door.gdshader, door_ghost.gdshader).
#include "res://shaders/world/terrain_common.gdshaderinc"

uniform sampler2D door_sdf : filter_linear, repeat_disable;   // x doors (23/24/25), y gates (26/28), z/w smooth/raw doors
uniform int channel = 0;              // 0 doors, 1 gates
uniform vec3 base_color : source_color = vec3(0.61, 0.18, 0.27);
uniform vec3 key_color = vec3(1.0, 0.2, 0.25);
uniform float time_offset = 0.0;
uniform bool mask_mode = false;       // solidity check: pure white where the door covers the plane
uniform sampler2D door_code : filter_nearest, repeat_disable;   // per-tile door code * 20 (R8)
uniform int my_code = 0;

// true on tiles that are not this door id at all (open air, keys, other doors): the smooth shared SDF
// bulges a little past the door's tiles, and nothing of a door may cover an open tile
bool not_mine(vec2 p) {
	ivec2 tp = clamp(ivec2(floor(p)), ivec2(0), ivec2(level_size) - 1);
	int c = int(texelFetch(door_code, tp, 0).r * 255.0 / 20.0 + 0.5);
	return c != my_code;
}

// true where this fragment belongs to ANOTHER door id (a neighbouring region sharing the SDF)
bool foreign_door(vec2 p) {
	ivec2 tp = clamp(ivec2(floor(p)), ivec2(0), ivec2(level_size) - 1);
	int c = int(texelFetch(door_code, tp, 0).r * 255.0 / 20.0 + 0.5);
	return c != 0 && c != my_code;
}


float door_sd(vec2 p) {
	vec4 t = textureLod(door_sdf, p / level_size, 0.0);
	return channel == 0 ? t.x : t.y;
}

float door_sd_raw(vec2 p) {
	vec4 t = textureLod(door_sdf, p / level_size, 0.0);
	return channel == 0 ? t.w : t.y;
}

float door_height(vec2 p) {
	float sf = door_sd(p);
	if (sf < 0.0) return -2.6;
	float relief = cobbles(p * 1.1 + fbm2(p * 0.3) * 0.5) * 0.12 + fbm3(p * 0.9) * 0.05;
	return Z_FG_TOP * round_prof(sf / 0.45) + 0.22 * smoothstep(0.5, 3.0, door_sd_raw(p)) + relief * smoothstep(0.0, 0.5, sf);
}

