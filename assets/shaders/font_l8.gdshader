shader_type canvas_item;

// 将单通道 L8 字库图集的 R 分量映射为 Alpha 通道，支持主色与半透明调节
void fragment() {
	float lum = texture(TEXTURE, UV).r;
	COLOR = vec4(COLOR.rgb, lum * COLOR.a);
}
