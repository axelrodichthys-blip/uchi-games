// 灰色の地面。1m と 10m のグリッド線で「歩いている感」を出す。フォグで遠くは消える。
shader_type spatial;
render_mode cull_back;

uniform vec3 base_color : source_color = vec3(0.45, 0.46, 0.48);
uniform vec3 line_color : source_color = vec3(0.36, 0.37, 0.39);
uniform float line_width = 0.03;
uniform vec3 steep_color : source_color = vec3(0.36, 0.30, 0.27);
uniform float steep_angle_deg = 46.0;   // これより急な斜面を steep_color に寄せる（Tuning.slope_max_angle と合わせる）

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid(vec2 p, float cell, float width) {
	vec2 g = abs(fract(p / cell - 0.5) - 0.5) * cell;
	float d = min(g.x, g.y);
	// 距離に応じて線を太らせてチラつきを抑える
	float w = width + fwidth(d);
	return 1.0 - smoothstep(width, w, d);
}

void fragment() {
	float small = grid(world_pos.xz, 1.0, line_width);
	float big = grid(world_pos.xz, 10.0, line_width * 2.5);
	float mix_amount = max(small * 0.5, big);
	vec3 color = mix(base_color, line_color, mix_amount);
	float cos_limit = cos(radians(steep_angle_deg));
	float steep = 1.0 - smoothstep(cos_limit - 0.06, cos_limit + 0.06, world_normal.y);
	ALBEDO = mix(color, steep_color, steep * 0.85);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
