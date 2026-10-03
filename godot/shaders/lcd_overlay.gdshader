shader_type canvas_item;
render_mode blend_mul, unshaded;

// 原 roomview 的 4px 点阵与内阴影；只叠在房间上，HUD 保持在其上方。
void fragment() {
	vec2 pixel = UV / SCREEN_PIXEL_SIZE;
	vec2 extent = vec2(1.0) / SCREEN_PIXEL_SIZE;
	float radius = length(mod(pixel, 4.0) - vec2(2.0));
	float dot_alpha = (1.0 - smoothstep(1.0, 1.2, radius)) * 0.16 * 0.55;
	vec3 dots = mix(vec3(1.0), vec3(46.0, 58.0, 36.0) / 255.0, dot_alpha);
	vec2 edge = min(pixel, extent - pixel);
	float shade_alpha = exp(-min(edge.x, edge.y) / 12.0) * 0.35;
	vec3 shade = mix(vec3(1.0), vec3(30.0, 40.0, 20.0) / 255.0, shade_alpha);
	COLOR = vec4(dots * shade, 1.0);
}
