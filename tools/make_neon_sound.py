#!/usr/bin/env python3
# ネオン街の環境音をループ音源として式で生成する（外部素材を使わない）。
#   python3 tools/make_neon_sound.py [出力.wav]
# 中身: 低い唸り（街の遠鳴り）+ 電気のハム（50Hz とその倍音）+ ときどき看板がジジッと鳴る。継ぎ目はクロスフェード。
import math, random, struct, sys, wave

OUT = sys.argv[1] if len(sys.argv) > 1 else "game/assets/audio/neon_hum.wav"
RATE = 22050
SECONDS = 8.0
N = int(RATE * SECONDS)
random.seed(21)

lp = 0.0
lp2 = 0.0
buzzes = []   # [開始サンプル, 周波数, 長さ]
samples = []
for i in range(N):
    t = i / RATE
    # 遠くの街の唸り: 低域に寄せたノイズ
    x = random.uniform(-1.0, 1.0)
    lp += 0.03 * (x - lp)
    lp2 += 0.10 * (lp - lp2)
    rumble = lp2 * 6.0

    # 電気のハム: 50Hz と倍音。ゆっくり強さが揺れる
    sway = 0.8 + 0.2 * math.sin(2 * math.pi * t / SECONDS * 2.0)
    hum = (math.sin(2 * math.pi * 50.0 * t) * 0.5
           + math.sin(2 * math.pi * 100.0 * t) * 0.22
           + math.sin(2 * math.pi * 150.0 * t) * 0.10) * 0.28 * sway

    # 看板のジジッ: ときどき短く高い帯域のノイズが鳴る
    if random.random() < 0.00012:
        buzzes.append([i, random.uniform(2200.0, 5200.0), random.randint(600, 2600)])
    buzz = 0.0
    for b in buzzes:
        k = i - b[0]
        if 0 <= k < b[2]:
            env = math.exp(-k / (b[2] * 0.35))
            flick = 1.0 if math.sin(2 * math.pi * 47.0 * k / RATE) > -0.3 else 0.2
            buzz += 0.06 * env * flick * math.sin(2 * math.pi * b[1] * k / RATE)
    buzzes = [b for b in buzzes if i - b[0] < b[2]]

    samples.append(rumble + hum + buzz)

# ループの継ぎ目: 末尾 0.8 秒を先頭にクロスフェード
fade = int(RATE * 0.8)
out = []
for i in range(N - fade):
    if i < fade:
        w = i / fade
        out.append(samples[i] * w + samples[N - fade + i] * (1.0 - w))
    else:
        out.append(samples[i])
peak = max(abs(v) for v in out)
with wave.open(OUT, "wb") as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(RATE)
    wf.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v / peak * 0.8)) * 32767)) for v in out))
print(f"[neon] {OUT}: {len(out) / RATE:.2f} 秒, {RATE} Hz, mono 16bit")
