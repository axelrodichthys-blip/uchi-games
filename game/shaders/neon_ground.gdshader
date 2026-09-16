// ネオン街の路面。濡れたアスファルトに水たまりが散り、両側の看板の色が縦に伸びて映り込む。
// テクスチャは使わず、すべて式で描く。看板の位置は「道に沿って一定間隔」と決め打ちして近似する。
shader_type spatial;
render_mode cull_back;

uniform vec3 asphalt_color : source_color = vec3(0.075, 0.080, 0.098);
uniform vec3 puddle_color : source_color = vec3(0.035, 0.040, 0.058);
uniform vec3 walk_color : source_color = vec3(0.105, 0.108, 0.125);   // 歩道
uniform vec3 neon_a : source_color = vec3(1.00, 0.24, 0.50);          // ピンク
uniform vec3 neon_b : source_color = vec3(0.17, 0.90, 1.00);          // シアン
uniform vec3 neon_c : source_color = vec3(1.00, 0.83, 0.28);          // 黄
uniform float puddle_scale = 0.09;      // 水たまりの大きさ（小さいほど大きな水たまり）
uniform float puddle_amount = 0.55;     // 水たまりの量 0〜1
uniform float street_half = 9.0;        // 道の半分の幅 m（この外は歩道）
uniform float sign_spacing = 13.0;      // 看板の間隔 m（映り込みの縞の間隔）
uniform float reflect_strength = 1.0;   // 映り込みの強さ
uniform bool cheap = false;             // 軽くする（細かいノイズを省く。スマホ向け）

varying vec3 world_pos;
varying vec3 world_normal;

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

// 看板ごとの色。道の左右（side）と、道に沿った区画（cell）で決める
vec3 sign_color(float cell, float side) {
	float h = hash21(vec2(cell, side));
	if (h < 0.38) {
		return neon_a;
	} else if (h < 0.72) {
		return neon_b;
	}
	return neon_c;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;   // p.x = 左右, p.y = 道に沿った向き（ワールドの z）
	float flat_ground = smoothstep(0.90, 0.985, world_normal.y);

	// 道と歩道
	float street = 1.0 - smoothstep(street_half - 0.6, street_half + 0.6, abs(p.x));
	vec3 base = mix(walk_color, asphalt_color, street);
	base *= cheap ? 1.0 : 1.0 + (vnoise(p * 2.3) * 0.16 - 0.08);

	// 水たまり
	float n = vnoise(p * puddle_scale);
	if (!cheap) {
		n = n * 0.62 + vnoise(p * puddle_scale * 3.1 + 11.0) * 0.38;
	}
	float edge = 1.0 - puddle_amount;
	float puddle = smoothstep(edge, edge + 0.10, n) * flat_ground * street;
	vec3 col = mix(base, puddle_color, puddle);

	// 看板の映り込み: 道に沿って一定間隔に並ぶ光が、路面で縦（z 方向）に伸びる
	float side = p.x < 0.0 ? -1.0 : 1.0;
	float cell = floor(p.y / sign_spacing);
	float in_cell = fract(p.y / sign_spacing);
	vec3 c1 = sign_color(cell, side);
	vec3 c2 = sign_color(cell + 1.0, side);
	vec3 neon = mix(c1, c2, smoothstep(0.35, 1.0, in_cell));
	// 建物側ほど強く、道の中央に向かって薄れる。細かい揺らぎで水面らしくする
	// 道の中央にも薄く色が届くようにして、足元が真っ暗にならないようにする
	float from_edge = 0.25 + 0.75 * smoothstep(0.0, street_half, abs(p.x));
	float wobble = cheap ? 0.85 : 0.65 + 0.35 * vnoise(vec2(p.x * 1.6, p.y * 0.22 + TIME * 0.05));
	float mirror = from_edge * wobble * street * reflect_strength;
	float glow = mirror * (0.25 + 0.75 * puddle);

	col += neon * glow * 0.55;
	ALBEDO = col;
	EMISSION = neon * glow * 0.35;
	ROUGHNESS = mix(0.85, 0.08, puddle);
	SPECULAR = mix(0.15, 0.85, puddle);
	METALLIC = 0.0;
}
