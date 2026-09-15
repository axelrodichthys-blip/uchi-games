# REFERENCE_GUIDE.md — キャラクターシートとワールド資料の作り方

ChatGPT などで画像を作るときの「何を・どの角度で・どう描くか」のガイド。
ここに書いた要件を満たす画像があれば、Claude 側で 3D 化（bpy スクリプト or 画像→3D サービス）と
Mixamo での歩行アニメ付けに進める。

---

## 1. 先に決めておくこと（3D 化の前提）

| 項目 | 推奨 | 理由 |
|---|---|---|
| 身体の構造 | **人型。腕・脚がはっきり分かれて見える** | Mixamo の自動リグは「頭・両手首・両肘・両膝・股」の位置を指定する方式。脚が隠れていると失敗する |
| 長いコート | **膝上まで、または前が割れている**（脚が見える） | 足首まで覆う筒状のコートは、歩くと脚が布を貫通する。裾は「布」ではなく「短いスカート状」として扱える長さに |
| 身体の色 | 参考画像では **真っ黒ではなく濃いグレー（炭色）で陰影あり** | 真っ黒のシルエットは AI の 3D 生成が形を読めない。最終的な「真っ黒」は Godot 側の材質で再現する |
| 目 | 白い丸い点 2 つ（顔の前面にはっきり） | 向きの目印になる。感情表現もここで |
| ポーズ | **A ポーズ**（腕を体から 30〜45 度開く）、脚は肩幅、指は自然に開く | T ポーズより肩まわりが自然に変形し、コートとも干渉しにくい |
| 頭身 | 4〜5 頭身、身長 1.5〜1.6 m 想定 | ローポリ・スタイライズド向き。ワールドの箱や柱との比率もこれで決める |
| 持ち物 | 最初は **無し**（帽子のみ） | 杖・ランタン・鞄は別パーツとして後から追加できる。最初から持たせるとリグとアニメが難しくなる |

---

## 2. キャラクターシート：必要な画像の一覧

全部で 5 種類。**同じキャラ・同じ縮尺・同じ塗り**で揃えることが最重要。

### 2-1. 全身ターンアラウンド（必須・最重要）
- 角度: **正面 / 左側面 / 背面 / 右側面**（左右対称なら右側面は省略可）
- 追加: **正面斜め 45 度** 1 枚（立体感の確認用）
- 条件:
  - 全ての角度で A ポーズ、**同じ身長・同じ位置に頭・腰・足**（横一列に並べ、ガイド線で揃える）
  - 正射投影（パースなし。遠近で足が小さくならない）
  - 光は平坦（強い陰影・落ち影・逆光なし）。白またはごく薄いグレーの無地背景
  - 全身が画面に収まる（足先・帽子の先が切れない）
  - 文字やラベル無し（ラベル付きは別に作ってよいが、**無地の版が必須**）
- 出力: 横長、幅 2048px 以上、PNG

### 2-2. 顔・頭部のクローズアップ
- 正面・側面の 2 枚。帽子の形、目の位置と大きさ、顔（あるなら口や鼻）の有無を確定する
- 目が感情を出すなら「通常 / まばたき / 驚き / 見上げる」の 4 パターンも

### 2-3. 部位のディテール
- コートの裾・襟・袖口・継ぎ当て・ほつれ、帽子の折れ、靴（あるなら）を 1 枚に並べる
- 「くたびれ方」はここで決める。3D にするときは **形で表現できるもの**（折れ、破れ、裾の不揃い）が有効。色ムラや汚れは材質側で少し入れる程度

### 2-4. カラーパレット
- キャラに使う色 3〜5 色を四角い色見本で並べ、**16 進コード**（例 #1a1a1e）を添える
- 「黒」も真っ黒 #000000 ではなく、少し青や紫に寄せた黒（例 #101014）を検討

### 2-5. イメージ画（雰囲気用・任意）
- 風景の中を歩いている絵。3D 化には使わないが、「この雰囲気」を Claude が読み取るための資料

---

## 3. ChatGPT に渡すプロンプト例

英語のほうが安定する。まずキャラの基本設定を 1 回で固定し、以降は「同じキャラで」と続ける。

### 基本設定（最初に 1 回）
```
A stylized low-poly-friendly game character design: a small wandering traveler.
Dark charcoal grey body (NOT pure black, keep soft shading so the 3D form reads),
two simple round white eyes, a tall pointed wizard-style hat that is slightly bent and worn,
a long weathered coat that ends just above the knees with a slit at the front so both legs are clearly visible,
simple arms and legs like a human, mitten-like simple hands, simple boots.
Proportions about 4.5 heads tall. Flat shading, no texture detail, muted palette.
Plain white background, no text.
```

### 全身ターンアラウンド
```
Character turnaround sheet of the same traveler character.
Four views side by side in one row: front view, left side view, back view, right side view.
A-pose: arms held about 40 degrees away from the body, legs shoulder-width apart, fingers relaxed.
Orthographic projection, exact same scale and height in every view, head/hip/feet aligned on the same horizontal lines.
Flat even lighting, no cast shadows, no perspective, no ground, plain white background, no text or labels.
Wide image, high resolution.
```
（続けて）
```
Same character, same style: front three-quarter view, A-pose, full body, plain white background, no text.
```

### 顔と表情
```
Same character: close-up of the head, front view and side view side by side.
Show the worn pointed hat shape and the two round white eyes clearly. Flat lighting, plain white background, no text.
```
```
Same character: four expression studies using only the eyes — neutral, blinking, surprised (eyes wider), looking up.
Head only, front view, same size, in one row. Plain white background, no text.
```

### ディテール
```
Same character: detail sheet of the coat hem, collar, sleeve cuffs, patches and frayed edges, the bent tip of the hat, and the boots.
Each detail drawn separately on a plain white background, flat shading, no text.
```

### パレット
```
Color palette for the same character: 3 to 5 flat color swatches in a row with hex codes written under each swatch.
Include the dark charcoal body color, the hat/coat color, the eye white, and one accent color.
```

### 避けたいもの（プロンプトの末尾に足すと安定する）
```
No dramatic lighting, no cast shadows, no motion blur, no flowing cloth, no overlapping limbs,
no hands in pockets, no hidden feet, no cropped body parts, no glow effects, no background scenery,
only one character, no text or labels.
```

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
- リポジトリの `docs/reference/character/` と `docs/reference/worlds/<world名>/` に置く（GitHub のブラウザ画面からアップロードできる: Add file → Upload files）
- 3D 化の作業は Claude がクラウド側で bpy スクリプトを書いて進める。結果は GitHub Pages の URL で確認する
