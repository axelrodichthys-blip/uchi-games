# MIXAMO_GUIDE.md — キャラに本物の人間の動きを付ける手順

Ghost of Tsushima や RE4 のような動きは、俳優のモーションキャプチャを合成したもの。
数式（今の `traveler.gd`）ではそこまで行かないので、モーションキャプチャ由来のアニメを
無料で配っている **Mixamo（Adobe）** を使う。Mixamo の操作はブラウザだけで完結する。

流れ: Claude がメッシュを書き出す → **ユーザーが Mixamo で自動リグ + アニメを選んで FBX を落とす** → Claude が .glb に変換して Godot に組み込む

## 0. 今できているもの（2026-09-15 に一通り通った）
- `docs/reference/character/traveler_apose.obj` … 仮キャラの A ポーズのメッシュ（Blender の `tools/blender/build_traveler_apose.py` で生成）
- `docs/reference/mixamo/*.fbx` … ユーザーが Mixamo で落とした 10 本
- `tools/blender/mixamo_fbx_to_glb.py` … Mixamo の FBX をまとめて .glb にする変換スクリプト（大きさの正規化と材質の復元込み）
- `game/assets/traveler_mixamo.glb` … 変換結果。`game/scenes/player/traveler_rig.gd` が AnimationTree で動かしている

分かったこと:
- Mixamo は OBJ の単位を cm と解釈するので、FBX は 100 倍小さく戻ってくる。変換で元 OBJ の高さに合わせる
- Mixamo は材質を 1 つにまとめる。変換で元 OBJ の面に一番近い面の材質を写して復元する
- Blender の材質色はリニアなので、Godot と同じ見た目にするには sRGB → リニア変換して渡す
- 「In Place」版の Walking は約 1.5 m/s、Running は約 2.4 m/s を想定した動き（`game/tools/inspect_glb.gd` で計測）。ゲームの速度に合わせて再生速度を変えている

本キャラのデザインが決まったら、同じ手順でそのメッシュに差し替える。Mixamo のアニメはリグの骨名が共通なので、あとから何度でも当て直せる。

## 0-b. 本キャラ（2026-09-18 に用意した。ここからはこちらを使う）

確定ターンアラウンド 2 枚からメッシュを組み立てた。**Mixamo に渡すのはポンチョ・帽子を外した姿**で、
ポンチョと帽子はリグが付いたあとに被せる（Mixamo の自動リグをテント型の布でつまずかせないため）。

| ファイル | 内容 |
|---|---|
| `tools/blender/build_traveler.py` | 本キャラのメッシュを組み立てる（bpy）。寸法は確定画像の実測値 |
| `docs/reference/character/traveler_body.obj` | **Mixamo にアップロードするのはこれ**（ポンチョ・帽子なし、A ポーズ、高さ 1.30 m） |
| `docs/reference/character/traveler_body_height.txt` | 上の高さ。変換時に渡す |
| `game/assets/traveler_outfit.glb` | ポンチョ + 帽子。リグの後に被せる |
| `game/assets/traveler_preview.glb` | 完成形（見た目の確認用。ゲームでは読まない） |
| `tools/blender/add_outfit.py` | リグ済みの .glb にポンチョ + 帽子を被せて重みを付ける |
| `tools/model-view.sh` | .glb を四面から描いて基準画像と見比べる |

**本キャラの流れ**（仮キャラのときと違うのは 2 と 4）:

1. `blender --background --python tools/blender/build_traveler.py` … メッシュを作る（Claude）
2. `docs/reference/character/traveler_body.obj` を Mixamo にアップロードして自動リグ、アニメ 10 本を落とす（**ユーザー**。下の 1〜3 章の手順は同じ。置き場所だけ `docs/reference/mixamo_body/` にする）
3. `blender --background --python tools/blender/mixamo_fbx_to_glb.py -- docs/reference/mixamo_body game/assets/traveler_rigged.glb 1.3000 docs/reference/character/traveler_body.obj`
   （**身長は 1.6 ではなく 1.3000**。素体には帽子が無いため。値は `traveler_body_height.txt`）
4. `blender --background --python tools/blender/add_outfit.py -- game/assets/traveler_rigged.glb game/assets/traveler_outfit.glb game/assets/traveler_dressed.glb`
5. `blender --background --python tools/blender/add_cloth_bones.py -- game/assets/traveler_dressed.glb game/assets/traveler_cloth.glb`
   （ゲームが読むのは `traveler_cloth.glb`。ここまで来れば差し替え完了）

自動リグのマーカーを置くときの注意（本キャラ特有）:
- **あごは首の付け根**に置く。頭が大きいので、頭の真ん中に置くと首が伸びる
- 手は手袋の**手のひらの中心**、手首は**カフスの位置**
- 膝はほぼ出っ張りが無いので、脚の**真ん中より少し下**に置く
- 腕の開きは 21 度と浅め（ポンチョに収めるため）。Mixamo が腕を胴と誤認したら、
  `build_traveler.py` の `ARM_ANGLE` を 30 度に上げて作り直す（ポンチョから手が少し出るが、リグ優先）

## 1. Mixamo にアップロード（ブラウザ）
1. https://www.mixamo.com/ にアクセスし、Adobe アカウント（無料）でログイン
2. 右上の **Upload Character** を押す
3. GitHub の **`docs/reference/character/traveler_body.obj`**（本キャラ。仮キャラのときは `traveler_apose.obj`）を開き、右上の Download（または Raw）で保存したファイルをドロップする
   - 拡張子は .obj のまま（.mtl は不要）
4. 自動リグ画面で、マーカーを図の通りに置く: **あご / 両手首 / 両肘 / 両膝 / 股**
   - 「Use Symmetry」をオンにする
   - Skeleton LOD は「Standard Skeleton (65)」でよい
5. Next → 数十秒待つ → 歩くプレビューが出れば成功
   - 失敗する（手足がねじれる）場合は、マーカーを置き直す。それでもだめなら Claude に伝える（メッシュの形を直す）

## 2. アニメを選んでダウンロード（ブラウザ）
左の検索欄で以下を探し、右の Download を押す。**設定はすべて共通**:
- Format: **FBX Binary (.fbx)**
- Frames per Second: **30**
- Keyframe Reduction: **none**
- Skin: 最初の 1 本（Idle）だけ **With Skin**、残りは **Without Skin**（ファイルが軽くなる）
- 「In Place」のチェックがあるアニメ（Walking / Running など）は **オンにする**（その場で足踏みする版。移動はゲーム側で行う）

| 順 | 検索語 | ダウンロード名（このまま保存） | 用途 |
|---|---|---|---|
| 1 | Idle | Idle.fbx（With Skin） | 待機 |
| 2 | Walking | Walking.fbx | 歩く（In Place オン） |
| 3 | Running | Running.fbx | 走る（In Place オン） |
| 4 | Jump | Jump.fbx | ジャンプ（踏切〜着地が 1 本のもの） |
| 5 | Falling Idle | FallingIdle.fbx | 落下中 |
| 6 | Landing | Landing.fbx | 着地 |
| 7 | Left Turn | LeftTurn.fbx | その場で左を向く |
| 8 | Right Turn | RightTurn.fbx | その場で右を向く |
| 9 | Walking Backwards | WalkingBackwards.fbx | 後退（In Place オン） |
| 10 | Look Around | LookAround.fbx | 待機の変化（任意） |

同じ名前で複数の候補が出るので、プレビューを見て自然なものを選ぶ。名前は上の表に合わせてファイル名を変えておくと、そのままアニメ名になる。

## 3. GitHub に置く（ブラウザ）
リポジトリの **`docs/reference/mixamo_body/`**（本キャラ。仮キャラのときは `docs/reference/mixamo/`）に、Add file → Upload files でまとめてアップロードする。
1 本あたり 1〜4MB。合計 30MB くらいまでなら問題ない。

## 4. あとは Claude がやること
本キャラは 0-b 章の 3〜5 を順に流す（変換 → ポンチョを被せる → 揺れの骨）。
仮キャラのときは `blender --background --python tools/blender/mixamo_fbx_to_glb.py -- docs/reference/mixamo game/assets/traveler_mixamo.glb` の 1 本だけだった。
そのあと Godot に読み込み、AnimationTree のブレンドを確認して、GitHub Pages で歩いてもらう。

## 5. 期待できること・できないこと
- できる: 人間の歩き・走り・ジャンプ・振り向きの自然さ（モーションキャプチャなので本物の動き）
- 一部: 動きの「つなぎ」の滑らかさは AnimationTree の作り込み次第。有名ゲームはここに専門チームを置いている
- できない: そのゲーム固有のアニメの再現（著作物なので）。同系統の動きを Mixamo から選ぶ
