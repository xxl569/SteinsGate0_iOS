shader_type canvas_item;

// MAGES. 灰度转场遮罩着色器（mask.mpk 灰度图控制平滑擦除进度）
uniform sampler2D mask_tex : filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float softness : hint_range(0.01, 0.5) = 0.08;
uniform bool invert_mask = false;

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float m = texture(mask_tex, UV).r;
	if (invert_mask) {
		m = 1.0 - m;
	}
	float p = mix(-softness, 1.0 + softness, progress);
	float alpha_factor = smoothstep(p - softness, p + softness, m);
	COLOR = vec4(base.rgb, base.a * alpha_factor);
}
