// Menu pass: dots sized from each fragment's own colour on the shared grid, so text strokes keep their shape.
shader_type canvas_item;

#include "res://shaders/halftone.gdshaderinc"

uniform float cell = 4.0;

void fragment() {
	vec4 src = COLOR;
	vec2 px = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec4 amounts = vec4(ink_amount(src.rgb, 0), ink_amount(src.rgb, 1), ink_amount(src.rgb, 2), ink_amount(src.rgb, 3));
	// Dark ink (text, borders) prints solid so small glyphs stay legible; light paper keeps its dots.
	amounts.w = mix(amounts.w, 1.0, smoothstep(0.55, 0.85, amounts.w));
	COLOR = vec4(print_inks(px, amounts, cell), src.a);
}
