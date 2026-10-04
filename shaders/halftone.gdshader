// Full-screen pass: each dot's size comes from the scene colour at its cell centre.
shader_type canvas_item;
render_mode unshaded;

#include "res://shaders/halftone.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float cell = 4.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float pulse = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE;
	vec2 px = SCREEN_UV / ps;
	float sz = cell * (1.0 + pulse);
	vec4 amounts;
	for (int ch = 0; ch < 4; ch++) {
		amounts[ch] = ink_amount(texture(screen_tex, cell_center(px, ch, sz) * ps).rgb, ch);
	}
	vec3 col = print_inks(px, amounts, sz);
	// Paper fibre grain and a manuscript vignette.
	col *= 0.96 + 0.04 * hash(floor(px * 0.5));
	vec2 v = SCREEN_UV - 0.5;
	col *= 1.0 - 0.35 * dot(v, v);
	COLOR = vec4(mix(texture(screen_tex, SCREEN_UV).rgb, col, strength), 1.0);
}
