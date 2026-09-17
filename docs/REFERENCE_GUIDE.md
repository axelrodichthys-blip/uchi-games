# REFERENCE_GUIDE.md — キャラクターシートとワールド資料の作り方

ChatGPT などで画像を作るときの「何を・どの角度で・どう描くか」のガイド。
ここに書いた要件を満たす画像があれば、Claude 側で 3D 化（bpy スクリプト or 画像→3D サービス）と
Mixamo での歩行アニメ付けに進める。

---

## 1. 先に決めておくこと（3D 化の前提）

**基準は `docs/reference/character/` の確定ターンアラウンド 2 枚**（`traveler_turnaround_poncho.png` / `traveler_turnaround_underclothes.png`、2026-09-17 確定）。
形と頭身のもとになった手描きスケッチは `sketches/`。色は `docs/reference/character/README.md` のパレットで確定済み。
以下はこれを 3D 化・画像化するときの扱い。

| 項目 | スケッチから決まること | 3D 化での扱い |
|---|---|---|
| 身体の構造 | 丸い頭 + **細い首** + 細身の胴。腕・脚は長くて細い。**手は 5 本指**（親指 + 4 本）、**足は 3 本のつま先**の丸い塊（手と足で本数が違う） | Mixamo の自動リグは「頭・両手首・両肘・両膝・股」を指定する方式。**ポンチョを外した姿（02）で A ポーズのメッシュを渡す** |
| ポンチョ | 肩からすねの中ほどまでのテント型。左胸のボタン 1 つで留め、前は重ね合わせ。**腕は中に隠れて見えない** | リグの後に Blender で被せ、胴の骨 + 布の骨の鎖に重みを付ける（`tools/blender/add_cloth_bones.py`）。脚との干渉は SpringBone の当たりで押し出す |
| 頭身 | 素体で約 5 頭身。脚が全高の約半分。完成形は帽子の先まで入れて縦長 | **身長は帽子の先まで 1.6 m**（2026-09-17 決定）。`mixamo_fbx_to_glb.py` の `TARGET_HEIGHT` がこの値。身体だけなら約 1.28 m の小柄な旅人 |
| 身体の色 | 真っ黒（目だけ白い楕円）。口・鼻なし | 画像生成では **濃い炭色 + 弱い陰影**で頼む（真っ黒だと形が読めない）。真っ黒は Godot の材質で再現 |
| 衣装の色 | 確定画像から抽出済み | 帽子・ポンチョ #BAA990 / 身体 #3A3937 / 目 #F2EDE3 / ブーツ #665C51 / ボタン #877A6A / ベスト #C4B098 / 手袋 #DBCBB9 / 半ズボン #9C8970 / ベルト・鞄 #6C5747 |
| 目 | 縦長の楕円の白 2 つ。帽子のつばと襟の間の黒い帯に見える | 向きの目印。感情表現もここで |
| ポーズ | — | **A ポーズ**（腕を 30〜45 度開く）、脚は肩幅。ポンチョ姿の絵でも中の腕は A ポーズのつもりで |
| 持ち物 | 腰の後ろの鞄（ベルトで留める） | 鞄は胴の骨に付ける小さな別パーツ。杖・ランタンは無し |

---

## 2. キャラクターシート：必要な画像の一覧

全部で 5 種類。**同じキャラ・同じ縮尺・同じ塗り**で揃えることが最重要。

### 2-1. 全身ターンアラウンド（必須・最重要）
- 角度: **正面 / 左側面 / 背面 / 右側面**（左右対称なら右側面は省略可）
- 追加: **正面斜め 45 度** 1 枚（立体感の確認用）
- 条件:
  - 全ての角度で同じ立ち姿（ポンチョ姿は腕が見えないので A ポーズの指定は不要。ポンチョ無しの版は A ポーズ）、**同じ身長・同じ位置に帽子の先・つば・裾・靴底**（横一列に並べ、ガイド線で揃える）
  - 正射投影（パースなし。遠近で足が小さくならない）
  - 光は平坦（強い陰影・落ち影・逆光なし）。白またはごく薄いグレーの無地背景
  - 全身が画面に収まる（足先・帽子の先が切れない）
  - 文字やラベル無し（ラベル付きは別に作ってよいが、**無地の版が必須**）
- 出力: 横長、幅 2048px 以上、PNG

### 2-2. 顔・頭部のクローズアップ
- 正面・側面の 2 枚。帽子の形、目の位置と大きさ、顔（あるなら口や鼻）の有無を確定する
- 目が感情を出すなら「通常 / まばたき / 驚き / 見上げる」の 4 パターンも

### 2-3. 部位のディテール
- 帽子の継ぎ当て・つば、ポンチョのボタンと合わせ目・裾、ブーツのカフス、手袋、ベルトのバックル、腰の鞄を 1 枚に並べる
- 「くたびれ方」はここで決める。3D にするときは **形で表現できるもの**（折れ、破れ、裾の不揃い）が有効。色ムラや汚れは材質側で少し入れる程度

### 2-4. カラーパレット
- キャラに使う色 3〜5 色を四角い色見本で並べ、**16 進コード**（例 #1a1a1e）を添える
- 「黒」も真っ黒 #000000 ではなく、少し青や紫に寄せた黒（例 #101014）を検討

### 2-5. イメージ画（雰囲気用・任意）
- 風景の中を歩いている絵。3D 化には使わないが、「この雰囲気」を Claude が読み取るための資料

---

## 3. ChatGPT に渡すプロンプト（1 画像 = 1 セッション方式）

**方式**: 画像を 1 枚作るたびに ChatGPT の新しいチャットを開く。前のやり取りに頼れないので、
**毎回「スケッチを添付 + キャラの説明の全文 + その画像の指定 + 避けたいもの」の 4 点セット**で渡す。

### 毎回の手順
1. 新しいチャットを開く
2. `docs/reference/character/traveler_turnaround_poncho.png` を添付する（衣装の中身・素体が要る画像は `traveler_turnaround_underclothes.png` も添付）。
   この 2 枚は塗り・色・線の太さまで確定した基準なので、**手描きスケッチより優先して添付する**
3. 下の **共通ブロック A**（キャラの説明）をそのまま貼る（色の 16 進コードまで入っている）
4. 続けて、作りたい画像の **ブロック B** を貼る
5. 最後に **共通ブロック C**（避けたいもの）を貼る
6. 出来た画像を `docs/reference/character/` に、ファイル名に内容を入れて保存する（例 `traveler_turnaround.png`）

### 共通ブロック A: キャラの説明（毎回そのまま貼る）
```
Reference: the attached turnaround sheet is the ONLY source of truth for this character — shape, proportions, colors and shading style.
Match it exactly. Do not redesign, do not add details that are not in the reference.

Character: a small wandering traveler for a quiet, stylized low-poly 3D game.
- Overall silhouette: two stacked cones — a tall pointed hat on top, and a tent-shaped poncho below.
  Only two thin stick legs and a pair of big boots show below the poncho hem. The arms are hidden inside the poncho.
- Body: very dark charcoal #3A3937 (not pure black; keep faint shading so the form reads). A rounded head on a short thin neck,
  then a narrow torso. Two tall oval off-white eyes (#F2EDE3), no mouth, no nose.
  A small feather-like tuft at the top back of the head (hidden under the hat when worn).
- Hat: a tall, slightly worn cone whose tip leans a little backward; a short flat brim that curls up slightly at the edges;
  one round button with two slit holes on the front of the cone. Under the brim, the head is a dark band with the two white eyes.
- Poncho: one piece of cloth from the shoulders down to mid-shin, widening evenly like a tent; the hem is slightly wavy.
  A stand-up collar hides the lower half of the head so only the eyes show between the brim and the collar.
  Closed by ONE large round two-hole button on the viewer's left side of the chest; one front panel overlaps the other,
  making a single vertical seam down to the hem.
- Legs: thin dark sticks. Boots: big compared to the legs, with a folded-over cuff at the top and a rounded toe; boot height about equal to the visible leg.
- Colors (flat, muted, no gradients): hat and poncho #BAA990, boots #665C51, buttons #877A6A, body #3A3937, eyes #F2EDE3.
- Proportions: with the sole at 0 and the hat tip at 1.0 — boots 0–0.11, visible legs 0.11–0.21, poncho 0.21–0.74,
  eye band 0.74–0.80, brim at 0.80, hat cone 0.81–1.0. Poncho hem width about 0.42 of the total height.
Style: flat shading, clean simple shapes, no texture detail, muted palette, plain white background, no text.
```

### 共通ブロック C: 避けたいもの（毎回末尾に貼る）
```
No dramatic lighting, no cast shadows, no motion blur, no billowing cloth, no visible arms or hands outside the poncho (unless asked),
no face other than the two oval eyes, no neckless head (the head always sits on a short thin neck),
no sleeves on the vest, no mitten hands and no four-fingered hands (hands always have five fingers: a thumb and four fingers;
feet always have exactly three toes — hands and feet have different counts),
no cropped body parts, no glow effects, no background scenery, only one character, no text or labels.
```

### ブロック B: 作りたい画像ごとの指定（1 セッションに 1 つ）

**B-1 全身ターンアラウンド（✅ 2026-09-17 完了 → `traveler_turnaround_poncho.png`）**
```
Make a character turnaround sheet of this exact character.
Four views side by side in one row: front view, left side view, back view, right side view.
Standing straight, legs shoulder-width apart (the arms are inside the poncho, so no arm pose is visible).
Orthographic projection, exactly the same scale and height in every view, hat tip / brim / poncho hem / boot soles aligned on the same horizontal lines.
Flat even lighting, no perspective, no ground plane, plain white background, no text or labels. Wide image, high resolution.
```

**B-2 正面斜め 45 度**
```
Make a full-body front three-quarter view (turned about 45 degrees) of this exact character, standing straight.
Show the overlapping front panel of the poncho, the single chest button, and the patch on the hat.
Flat lighting, plain white background, no text.
```

**B-3 ポンチョを外した姿のターンアラウンド（✅ 2026-09-17 完了 → `traveler_turnaround_underclothes.png`）**
```
Make a character turnaround sheet of this exact character WITHOUT the poncho and WITHOUT the hat, in A-pose
(arms held about 40 degrees away from the body, legs shoulder-width apart, fingers relaxed).
Under the poncho the character wears: a SLEEVELESS vest (#C4B098) with a notched lapel collar and three round buttons,
a brown leather belt with a square buckle (#6C5747), short trousers ending mid-thigh with turned-up cuffs (#9C8970),
chunky five-fingered gloves (thumb plus four fingers) with cuffs (#DBCBB9), the same big cuffed boots (#665C51),
and a soft bag hanging from the belt at the back of the waist (#6C5747).
Arms and legs are the bare dark charcoal body. The rounded head on its short thin neck, with the small feather-like tuft at the top back, is uncovered.
Four views in one row: front, left side, back, right side. Orthographic, same scale, aligned. Flat lighting, plain white background, no text.
```

**B-4 素体のターンアラウンド（モデリングの基礎。手描きスケッチ `sketches/03` も一緒に添付）**
```
Make a character turnaround sheet of this exact character's bare body (no clothes, no hat), in A-pose.
A slim dark charcoal (#3A3937) figure: a rounded head on a short thin neck, then a narrow torso;
a small feather-like tuft at the top back of the head; two tall oval off-white eyes (#F2EDE3);
long thin arms with five-fingered hands (thumb plus four slender fingers); long thin legs;
rounded animal-like feet with exactly three toes each.
Four views in one row: front, left side, back, right side. Orthographic, same scale, aligned. Flat lighting, plain white background, no text.
```

**B-5 頭部のクローズアップ**
```
Make a close-up of this exact character's head with the hat on: front view and left side view side by side.
Show the worn cone with its slightly leaning tip, the short curling brim, the round stitched patch, the stand-up poncho collar,
and the two tall oval white eyes in the dark band between brim and collar. Flat lighting, plain white background, no text.
```

**B-6 目の表情**
```
Make four head-only studies of this exact character in one row, same size, front view, using ONLY the two oval eyes for expression:
neutral, blinking (eyes closed as thin lines), surprised (eyes wider and rounder), looking up (eyes shifted up).
Flat lighting, plain white background, no text.
```

**B-7 ディテール（ポンチョ無しの確定画像も一緒に添付）**
```
Make a detail sheet of this exact character, each item drawn separately on a plain white background, flat shading, no text:
the hat's round stitched patch and brim edge, the poncho's chest button and overlapping front seam, the wavy poncho hem,
one boot with its folded cuff and rounded toe, one chunky five-fingered glove with cuff, the belt buckle, and the bag on the back of the belt.
```

**B-8 カラーパレット（✅ 確定済み → `docs/reference/character/README.md`。作り直すときだけ）**
```
Make a color palette for this exact character: 5 flat color swatches in a row with the hex code written under each.
Body charcoal (very dark, slightly blue-tinted), hat and poncho faded sand beige, boots dark grey-brown, gloves off-white, one accent color for the button and patch.
Plain white background.
```

**B-9 イメージ画（雰囲気用・任意）**
```
Make a wide illustration of this exact character walking alone through a rainy grey landscape toward a single distant warm light,
seen from behind and slightly above, small in the frame. Flat low-poly style, muted 3-5 color palette (grey sky, dark wet ground, one warm light).
No text.
```

### うまくいかないとき
- 形が変わる → 「Follow the attached sketch exactly」を先頭に足し、変わった部分を名指しで直す（例 "the hat must be taller and thinner, like the sketch"）
- 腕が出てくる → 「the arms are inside the poncho and must not be visible」を B の末尾にも足す
- 首が無くなる（頭が胴に直結する）→ 「the head sits on a short thin neck, clearly separated from the torso」を B の末尾に足す
- 指が 4 本やミトンになる → 「five fingers: a thumb and four separate fingers on each hand」を B の末尾にも足す（手が写る B-3 / B-4 / B-7 で起きやすい）
- 足の指が 5 本になる → 「exactly three toes on each foot」を足す（**手は 5 本・足は 3 本**で本数が違うので、生成 AI は手に引きずられやすい）
- 4 面の大きさが揃わない → 「same height in all four views, aligned on guide lines」をもう一度書く。それでも駄目なら 1 面ずつ別セッションで作り、Claude 側で並べる

---

## 4. アニメーション一覧（人型・Mixamo で揃える）

Mixamo の自動リグをかけた後、以下を検索して取り込む（名前は Mixamo 上の検索語）。
Godot 側では AnimationTree でブレンドする。

| 用途 | 内容 | Mixamo の検索語（例） | 優先 |
|---|---|---|---|
| 待機 | 呼吸する立ち姿 | Idle / Breathing Idle | 必須 |
| 待機バリエーション | 周りを見回す、帽子を直す | Look Around / Idle variations | 中 |
| 歩く | 前進（ループ） | Walking | 必須 |
| 走る | 前進（ループ） | Running | 必須 |
| 後退 | 一人称・後ろ歩き用 | Walking Backwards | 中 |
| 横歩き | 一人称用 左 / 右 | Left Strafe Walk / Right Strafe Walk | 低 |
| 振り向き | その場で左 / 右に 90〜180 度 | Left Turn / Right Turn（または Turn 90 / 180） | 中 |
| ジャンプ | 踏切 → 滞空 → 着地（3 分割） | Jump（Jumping Up / Falling Idle / Landing） | 必須（ジャンプ採用のため） |
| 落下 | 段差から落ちるときの滞空 | Falling Idle | 中 |
| 着地 | 高いところから降りた後 | Landing / Hard Landing | 中 |
| 歩き始め / 止まる | 加減速の味付け | Walk Start / Walk Stop | 低（後回し） |
| 休む | 座る、しゃがんで景色を見る | Sitting / Crouch Idle | 低（雰囲気用） |

Mixamo での操作はユーザーがブラウザで行う（自動リグのマーカー指定、アニメの選択、FBX ダウンロード）。
FBX → .glb の変換と Godot への取り込みは Claude 側で bpy スクリプトを用意して行う。手順は必要になった時に提示する。

---

## 5. ワールドは画像から 3D 化できるか

**正確な再現は無理。雰囲気の再現はできる。** 理由:
- 画像→3D サービスは「1 つの物体」を作る道具で、風景全体を歩ける地形にはならない
- このゲームの見た目（ローポリ・単色・フォグ）は、Claude が地形・空・フォグ・小物を **手で組み立てる**ほうが向いている。画像は「設計図」として使う

つまり、ワールドの画像は「Claude が読み取って組み立てる資料」になる。**次の要素が揃っていると再現度が上がる。**

### 5-1. ワールド資料に含めてほしいもの（1 ワールドにつき）

| 資料 | 内容 | 何に使うか |
|---|---|---|
| キービジュアル 1〜2 枚 | 広めの引き画。**キャラを小さく入れて縮尺を示す**。空と地面の両方が写る | 色・光・フォグの濃さ・空の見え方を読み取る |
| カラーパレット | 空の上端 / 地平線 / 地面 / 目印 / アクセント の 3〜5 色 + 16 進コード | 材質・フォグ・空のグラデーションをそのまま設定する |
| 上から見た配置図 | 手描きで可。**一辺の長さ（例 300 m）**、開始地点、「見つけるもの」の位置、道、区画 | 地形の広さと物の配置 |
| 地面の質感メモ | 平ら / なだらかな起伏 / 段差、素材（濡れたアスファルト、砂、草、金属）、水たまりの有無 | 地形の形と足音の種類 |
| 小物リスト + 各 1〜2 枚 | 街灯、ベンチ、看板、木、岩、傘 など。**正面 + 側面（または斜め 45 度）**、無地背景、平坦な光 | 各小物を個別に 3D 化する（ここは画像→3D も使える） |
| 空の説明 | 時間帯、雲の有無、太陽 / 月の位置と光の向き、光の色 | DirectionalLight と空のグラデーション |
| 効果のメモ | 雨の強さ、霧の濃さ、粒子（塵・雪・光）、光る物、反射 | パーティクルと後処理 |
| 音のメモ | 環境音、足音、BGM の雰囲気（文字で可） | 音の準備（画像とは別） |
| 歩き終えたときの気持ち | 一行で | 「見つけるもの」と演出の判断基準 |

### 5-2. ワールド画像のプロンプトの注意
- 「wide shot」「a tiny traveler figure for scale」「flat low-poly style」「muted 3-5 color palette」「no text」を入れる
- 写真調（photorealistic）にしない。細かいテクスチャは 3D 化で再現できないので、**平坦な塗り**で
- 小物は「1 枚に 1 個」「無地背景」「正面と側面」を守る。風景の中に埋もれた小物は取り出せない

---

## 6. 渡し方

- 画像は PNG のまま、ファイル名に内容を入れる（例 `traveler_turnaround.png`、`rain_key_visual_01.png`、`prop_streetlamp_front_side.png`）
- リポジトリの `docs/reference/character/`（手描きのスケッチは `docs/reference/character/sketches/`）と `docs/reference/worlds/<world名>/` に置く（GitHub のブラウザ画面からアップロードできる: そのフォルダを開いて Add file → Upload files。Claude とのチャットに直接添付してもよく、その場合は Claude がリポジトリに保存する）
- 3D 化の作業は Claude がクラウド側で bpy スクリプトを書いて進める。結果は GitHub Pages の URL で確認する
