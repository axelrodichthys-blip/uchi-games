#!/usr/bin/env python3
# 雨音のループ音源を式で生成する（外部素材を使わない）。
#   python3 tools/make_rain_sound.py [出力.wav]
# 中身: ざらついたノイズ（低域寄り）+ 高域のさらさら + ときどき近くに落ちる粒。継ぎ目はクロスフェード。
import math, random, struct, sys, wave

OUT = sys.argv[1] if len(sys.argv) > 1 else "game/assets/audio/rain_loop.wav"
RATE = 22050
SECONDS = 6.0
N = int(RATE * SECONDS)
random.seed(7)

lp = 0.0      # 低域（一段のローパス）
hp_prev = 0.0 # 高域（一段のハイパス）
x_prev = 0.0
samples = []
drips = []    # (開始サンプル, 周波数, 減衰)
for i in range(N):
    x = random.uniform(-1.0, 1.0)
    lp += 0.12 * (x - lp)                 # こもった雨のざわめき
    hp = 0.85 * (hp_prev + x - x_prev)    # さらさらした高域
    hp_prev, x_prev = hp, x
    # ゆっくり揺れる強弱（雨足）
    sway = 0.75 + 0.25 * math.sin(2 * math.pi * i / N * 3.0 + 1.0) * math.sin(2 * math.pi * i / N * 7.0)
    v = (lp * 1.6 + hp * 0.35) * sway
    # 近くの粒: たまに短い「ぴちょ」
    if random.random() < 0.00025:
        drips.append([i, random.uniform(1800.0, 4200.0), random.uniform(0.0008, 0.002)])
    for d in drips:
        t = i - d[0]
        if t >= 0:
            v += 0.12 * math.exp(-t * d[2]) * math.sin(2 * math.pi * d[1] * t / RATE)
    drips = [d for d in drips if i - d[0] < 3000]
    samples.append(v)

# ループの継ぎ目: 末尾 0.5 秒を先頭にクロスフェード
fade = int(RATE * 0.5)
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
print(f"[rain] {OUT}: {len(out) / RATE:.2f} 秒, {RATE} Hz, mono 16bit")
