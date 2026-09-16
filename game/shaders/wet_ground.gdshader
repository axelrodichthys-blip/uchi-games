// 雨に濡れた地面。暗い地面に水たまりが散り、水たまりは空を映す（粗さを下げて反射させる）。
// 水たまりの中では雨粒の波紋（輪）が次々に広がる。テクスチャは使わず、すべて式で描く。
shader_type spatial;
render_mode cull_back;

uniform vec3 base_color : source_color = vec3(0.15, 0.16, 0.18);
uniform vec3 puddle_color : source_color = vec3(0.10, 0.12, 0.16);
uniform vec3 ripple_color : source_color = vec3(0.60, 0.63, 0.68);
uniform vec3 sky_color : source_color = vec3(0.53, 0.55, 0.59);   // 水たまりに映る空の色（Environment のフォグ色と合わせる）
uniform float reflection_strength = 0.85;
uniform float puddle_scale = 0.07;      // 水たまりの大きさ（小さいほど大きな水たまり）
uniform float puddle_amount = 0.42;     // 水たまりの量 0〜1
uniform float ripple_density = 1.4;     // 波紋の密度（1m あたりの個数の目安）
uniform float ripple_speed = 1.1;       // 波紋が広がる速さ
uniform float ripple_rate = 0.6;        // 波紋の出る割合 0〜1（雨の量と連動。Tuning.rain_amount）
uniform float wet_roughness = 0.85;     // 水たまり以外の濡れた地面の粗さ

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 格子 1 マスに波紋 1 つ。位相をマスごとにずらして、次々に広がって消える
float ripples(vec2 p, float t) {
	vec2 cell = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash21(cell);
	vec2 center = (vec2(hash21(cell + 7.1), hash21(cell + 3.7)) - 0.5) * 0.4;
	float cycle_t = t * ripple_speed * (0.7 + 0.6 * h) + h * 7.0;
	float phase = fract(cycle_t);
	// 周期ごとに「この周期は波紋を出すか」を抽選し、出る割合を雨の量に合わせる
	if (hash21(cell + floor(cycle_t) * 0.371) > ripple_rate) {
		return 0.0;
	}
	float radius = phase * 0.28;
	float d = length(f - center);
	float ring = smoothstep(0.035, 0.0, abs(d - radius));
	return ring * (1.0 - phase) * (1.0 - phase);
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = vnoise(p * puddle_scale) * 0.62 + vnoise(p * puddle_scale * 3.3 + 11.0) * 0.38;
	float flat_ground = smoothstep(0.90, 0.985, world_normal.y);
	float edge = 1.0 - puddle_amount;
	float puddle = smoothstep(edge, edge + 0.10, n) * flat_ground;
	float rip = ripples(p * ripple_density, TIME) * puddle;
	// 濡れた地面の細かいムラ
	float grain = vnoise(p * 2.7) * 0.10 - 0.05;
	vec3 col = mix(base_color * (1.0 + grain), puddle_color, puddle);
	// 水たまりの映り込み: 視線が浅いほど空が強く映る（フレネル）。Compatibility では空の反射が弱いので式で足す
	float fresnel = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.0);
	float mirror = puddle * reflection_strength * (0.25 + 0.75 * fresnel);
	col = mix(col, sky_color, mirror);
	col += ripple_color * rip * 0.8;
	ALBEDO = col;
	ROUGHNESS = mix(wet_roughness, 0.08, puddle);
	SPECULAR = mix(0.12, 0.85, puddle);
	METALLIC = 0.0;
}
