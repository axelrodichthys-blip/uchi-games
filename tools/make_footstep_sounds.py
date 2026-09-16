#!/usr/bin/env python3
# 足音を式で生成する（外部素材を使わない）。
#   python3 tools/make_footstep_sounds.py
# 出力: game/assets/audio/step_stone_1..3.wav（乾いた地面）, step_wet_1..3.wav（濡れた地面・水たまり）
import math, random, struct, wave

RATE = 22050
OUT_DIR = "game/assets/audio"


def write(path, samples):
    peak = max(1e-6, max(abs(v) for v in samples))
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(RATE)
        wf.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v / peak * 0.9)) * 32767)) for v in samples))
    print(f"[footstep] {path}: {len(samples) / RATE:.2f} 秒")


def stone(seed):
    # 乾いた地面: 短い「トッ」。低い衝撃 + 高域の砂粒のノイズ
    rnd = random.Random(seed)
    n = int(RATE * 0.16)
    out = []
    lp = 0.0
    thump_f = rnd.uniform(70.0, 95.0)
    for i in range(n):
        t = i / RATE
        thump = math.sin(2 * math.pi * thump_f * t * (1.0 + 2.0 * math.exp(-t * 60.0))) * math.exp(-t * 55.0)
        x = rnd.uniform(-1.0, 1.0)
        lp += 0.35 * (x - lp)
        grit = (x - lp) * math.exp(-t * 45.0) * 0.5
        out.append(thump * 0.9 + grit)
    return out


def wet(seed):
    # 濡れた地面: 「ぴちゃ」。衝撃は弱く、水のはねる中高域ノイズが少し長く残る
    rnd = random.Random(seed)
    n = int(RATE * 0.22)
    out = []
    lp = 0.0
    bp_prev = 0.0
    x_prev = 0.0
    for i in range(n):
        t = i / RATE
        thump = math.sin(2 * math.pi * 80.0 * t) * math.exp(-t * 70.0) * 0.4
        x = rnd.uniform(-1.0, 1.0)
        lp += 0.5 * (x - lp)
        bp = 0.6 * (bp_prev + lp - x_prev)   # 中域寄りのシャワシャワ
        bp_prev, x_prev = bp, lp
        env = math.exp(-t * 22.0) * (1.0 - math.exp(-t * 400.0))
        splash = bp * env * 1.4
        # 小さな水滴の跳ね
        drop = 0.0
        if 0.05 < t < 0.12:
            drop = math.sin(2 * math.pi * rnd.uniform(1500.0, 2600.0) * t) * math.exp(-(t - 0.05) * 90.0) * 0.15
        out.append(thump + splash + drop)
    return out


for k in range(1, 4):
    write(f"{OUT_DIR}/step_stone_{k}.wav", stone(k))
    write(f"{OUT_DIR}/step_wet_{k}.wav", wet(10 + k))
