// Shared four-ink screen (woad, madder, ochre, iron-gall) so the scene and the menus print on one grid.
const vec3 PAPER = vec3(0.95, 0.90, 0.79);
const vec3 INK_C = vec3(0.36, 0.60, 0.70);
const vec3 INK_M = vec3(0.86, 0.34, 0.30);
const vec3 INK_Y = vec3(0.98, 0.82, 0.36);
const vec3 INK_K = vec3(0.16, 0.11, 0.09);
const float ANGLES[4] = float[](15.0, 75.0, 0.0, 45.0);

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// CMYK amount of channel `ch` (0=C 1=M 2=Y 3=K) for a colour.
float ink_amount(vec3 col, int ch) {
	float k = 1.0 - max(max(col.r, col.g), col.b);
	if (ch == 3) {
		return k;
	}
	float d = max(1.0 - k, 1e-4);
	float v = ch == 0 ? col.r : (ch == 1 ? col.g : col.b);
	return (1.0 - v - k) / d;
}

// Coverage (0..1) of a dot of the given ink amount at pixel `px` on a screen rotated by `ang`.
float dot_cov(vec2 px, float ang, float amount, float sz) {
	vec2 r = rot(px, ang);
	vec2 cell_c = (floor(r / sz) + 0.5) * sz;
	float radius = sqrt(clamp(amount, 0.0, 1.0)) * sz * 0.74;
	return 1.0 - smoothstep(radius - 0.8, radius + 0.8, length(r - cell_c));
}

// Cell centre (in pixels) of the screen for channel `ch` containing `px`.
vec2 cell_center(vec2 px, int ch, float sz) {
	float a = radians(ANGLES[ch]);
	return rot((floor(rot(px, a) / sz) + 0.5) * sz, -a);
}

vec3 print_inks(vec2 px, vec4 amounts, float sz) {
	vec3 col = PAPER;
	col *= mix(vec3(1.0), INK_C, dot_cov(px, radians(ANGLES[0]), amounts.x, sz));
	col *= mix(vec3(1.0), INK_M, dot_cov(px, radians(ANGLES[1]), amounts.y, sz));
	col *= mix(vec3(1.0), INK_Y, dot_cov(px, radians(ANGLES[2]), amounts.z, sz));
	col *= mix(vec3(1.0), INK_K, dot_cov(px, radians(ANGLES[3]), amounts.w, sz));
	return col;
}
