shader_type canvas_item;
// Faint dot grid, slow drifting glow and a vignette. Deliberately subtle.

uniform vec4 base_color : source_color = vec4(0.043, 0.051, 0.071, 1.0);
uniform vec4 dot_color : source_color = vec4(0.37, 0.90, 0.78, 1.0);
uniform vec4 glow_color : source_color = vec4(0.71, 0.55, 1.0, 1.0);
uniform float grid = 28.0;

void fragment() {
	vec2 px = FRAGCOORD.xy;
	vec2 cell = mod(px, grid) - grid * 0.5;
	float dot_mask = 1.0 - smoothstep(0.6, 1.4, length(cell));
	vec2 uv = SCREEN_UV;
	vec2 glow_pos = vec2(0.5 + 0.25 * sin(TIME * 0.05), 0.35 + 0.1 * cos(TIME * 0.07));
	float glow = smoothstep(0.75, 0.0, distance(uv, glow_pos));
	float vignette = smoothstep(1.1, 0.35, distance(uv, vec2(0.5)));
	vec3 col = base_color.rgb;
	col += glow_color.rgb * glow * 0.035;
	col += dot_color.rgb * dot_mask * 0.035 * vignette;
	col *= mix(0.75, 1.0, vignette);
	COLOR = vec4(col, 1.0);
}
