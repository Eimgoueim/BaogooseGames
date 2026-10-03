shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_radius : hint_range(0.0, 32.0) = 12.0;
uniform float corner_radius : hint_range(0.0, 128.0) = 24.0;
uniform vec2 rect_size = vec2(1.0);

float rounded_box_distance(vec2 point, vec2 half_size, float radius) {
	vec2 q = abs(point) - half_size + vec2(radius);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec2 half_size = max(rect_size * 0.5, vec2(0.5));
	vec2 point = (UV - vec2(0.5)) * rect_size;
	float distance_to_edge = rounded_box_distance(point, half_size, min(corner_radius, min(half_size.x, half_size.y)));
	float mask = 1.0 - smoothstep(-1.0, 1.0, distance_to_edge);
	vec2 step_uv = SCREEN_PIXEL_SIZE * blur_radius * 0.55;
	vec4 blurred = textureLod(screen_texture, SCREEN_UV, 1.2) * 0.2;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(step_uv.x, 0.0), 1.2) * 0.1;
	blurred += textureLod(screen_texture, SCREEN_UV - vec2(step_uv.x, 0.0), 1.2) * 0.1;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(0.0, step_uv.y), 1.2) * 0.1;
	blurred += textureLod(screen_texture, SCREEN_UV - vec2(0.0, step_uv.y), 1.2) * 0.1;
	blurred += textureLod(screen_texture, SCREEN_UV + step_uv, 1.2) * 0.1;
	blurred += textureLod(screen_texture, SCREEN_UV - step_uv, 1.2) * 0.1;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(step_uv.x, -step_uv.y), 1.2) * 0.1;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(-step_uv.x, step_uv.y), 1.2) * 0.1;
	COLOR = vec4(blurred.rgb, blurred.a * mask) * COLOR;
}
