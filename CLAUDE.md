# uchi-games — CLAUDE.md

幻想的な風景の中を旅人キャラクターが歩いて探索するだけの3Dゲーム。
戦闘・インベントリ・クエストなし。雰囲気と「歩く気持ちよさ」がすべて。

設計書（コンセプト・キャラ・ワールド・ロードマップ・アイデア置き場）は必ずこちらを参照：
@GAME_DESIGN.md

## 技術スタック（変更する場合は必ず相談）

- エンジン: **Godot 4.x（最新の安定版）**、言語は **GDScript**
- キャラ・小物のモデリング: **Blender**（GUI操作はしない。bpyスクリプトをこのリポジトリに置き、ヘッドレスで実行して .glb を書き出す）
- 歩行アニメ: Mixamo など外部サービスはユーザーがブラウザ側で操作する。必要になったら手順を提示する
- バージョン管理: Git / GitHub（origin = uchi-games）
- 公開先: itch.io（Web書き出しを優先、Windows版も同梱）
- ユーザーの実機: Windows 11 ノート、内蔵GPU。重い処理は避ける

## 作業環境は2種類ある（重要）

このリポジトリは **Claude Code on the web（Anthropicのクラウド）** と **ユーザーのWindows PC** の両方から作業する。
起動時に環境変数 `CLAUDE_CODE_REMOTE` を確認して、どちらで動いているか把握してから作業すること。

### クラウド（Linux サンドボックス）で動いているとき
- ユーザーは外出先。**実機で歩いて確認することはできない**
- **外出先PCには何もインストールしない。** ユーザーに頼む操作はブラウザで完結するものだけ（GitHub の設定、Pages の確認、ChatGPT や Mixamo などのブラウザ操作）。ソフト導入が要る作業は「自宅PCでやること」として HANDOFF.md に分けて書く
- ファイルシステムはセッションごとに作り直される。必要なツールは `tools/cloud-setup.sh` で入れる（Godot は GitHub リリースから、Blender は apt から）。このスクリプトはクラウド環境の「セットアップスクリプト」にも登録する
- GPU はない。見た目の確認は次の順で試す：
  1. `godot --headless` でのインポート・書き出し・スクリプトのエラーチェック（確実に動く）
  2. ソフトウェアレンダリング（xvfb + Mesa）でのスクリーンショット（動けば使う。動かなければ深追いしない）
  3. **Web書き出しを GitHub Pages に配置し、ユーザーがブラウザで歩いて確認する**（本命）
- Web書き出しの GitHub Pages 配置は、必要なヘッダーが付けられない制約があるので、Godot のスレッド無効設定か coi-serviceworker で対処する
- 成果は必ず GitHub に push する（push しないとユーザーには何も届かない）

### ユーザーの Windows PC で動いているとき
- Godot / Blender の実行ファイルパスは下の「環境メモ」を見る
- ユーザーが実機で歩いて確認できる。操作感の調整はここで行う

## アート方針（守ること）

- スタイライズド（ローポリ・単色/グラデーション・フォグ・パーティクル・後処理）
- **フォトリアル禁止。** 高解像度テクスチャ・高ポリゴン素材・写真スキャン素材は使わない
- 「広さ」は地形の面積ではなくフォグと地平線の見せ方で作る
- Webビルドは合計 200MB 以下を目標

## 作業の進め方

- ユーザーはゲーム制作が初めて。**判断が必要なこと以外は自走する。** 手順の説明より実行を優先する
- 判断を仰ぐのは次の場合だけ：見た目・操作感の好み、新しいライブラリや有料サービスの導入、設計書の方針変更、削除やリセットを伴う作業
- 常に「起動して歩ける状態」を壊さない。大きな変更は小さく分けて、都度動作確認する
- 作業の区切りごとに `git commit`（日本語の簡潔なメッセージ）。セッション終了時に `git push`
- 新しい素材・機能・ワールドを追加したら、GAME_DESIGN.md の該当箇所とロードマップを更新する
- 説明・コメント・コミットメッセージは日本語。報告は簡潔に。次に何を決めてほしいかを最後に一行で書く
- シェルスクリプトは bash、改行コードは LF（Windows で編集しても崩れないよう .gitattributes で固定する）
- 操作感に関わる数値（カメラ距離・追従速度・歩行速度・視野角・フォグ濃度など）は1つの設定ファイルにまとめ、散らばらせない
- 調整値をゲーム内でその場で変えられるデバッグパネル（F1で表示）を早い段階で用意する。ユーザーはこれで良い数値を見つけて、次のセッションに数値を伝える
- **報告の前に必ず自分でテストプレイし、自己採点して、合格点になるまで検証と修正を繰り返す**（ユーザーの要望。往復を減らすためのルール）。ユーザーに見せるのは自分で合格と判断したものだけ。最低限:
  - `godot --headless --path game res://tools/walk_test.tscn` を通す
  - 動きや見た目の変更は `tools/screenshot.sh`（連続コマ）や `tools/clip-view.sh`（クリップ単体）で撮り、自分の目で確認する。特に **キャラの向きが進行方向と一致しているか**、動作の切り替わりに不要な動きが挟まっていないか
  - Web 書き出しをブラウザ（headless Chromium）で起動確認する
  - 報告には「確認したこと / 確認できていないこと / 自己採点（10 点満点と減点理由）」を添える。自分で確認できないこと（実機の操作感など）はそう明記する

## セッションの始め方・終わり方

このリポジトリはクラウドと自宅PCの両方から触る。**GitHub 上の main が唯一の正**で、セッションは使い捨て。

1. 開始時:
   - まず `git pull` して最新を取り込む（クラウドでは取り直し直後なので実質不要だが、実行して損はない）。pull が衝突などで失敗したら、自分で解決せずユーザーに状況を伝える
   - `docs/HANDOFF.md`（前回の引き継ぎ）を読み、今日やる候補を1〜3個提示して確認を取る
2. 作業中: 区切りごとに `git commit`。ブランチや Pull Request は作らず **main に直接 push** する（ユーザーが明示的に頼んだときだけブランチを使う）
3. 終了時（ユーザーが「引き継ぎ」「終わり」と言ったとき、または作業の区切りで自分から）:
   - `docs/HANDOFF.md` を上書き更新する
     - 今どこまで動くか / 未完了のこと / 詰まっている点 / 次にやること / ユーザーに決めてほしいこと / 自宅PCでやること / **ユーザーがブラウザで確認できるURL**
   - 必ず `git push` まで行い、push が成功したことを報告の最後に一行で書く。**push されていない作業はユーザーには存在しないのと同じ**

## ディレクトリ構成（目安）

```
uchi-games/
  CLAUDE.md
  GAME_DESIGN.md
  docs/HANDOFF.md          引き継ぎメモ
  game/                    Godotプロジェクト（project.godot はここ）
    scenes/player/         キャラ・カメラ
    scenes/worlds/<name>/  ワールドごとに1ディレクトリ
    scenes/hub/            拠点・ワールド間移動
    shaders/
    assets/                .glb / 音 / 生成物
  tools/blender/           bpyスクリプト（キャラ生成など）
  tools/cloud-setup.sh     クラウド環境のツール導入
  tools/                   スクリーンショット・書き出しなどの補助スクリプト
  build/                   書き出し先（gitignore。GitHub Pages 用は別ブランチか docs/ 配下）
```

## 環境メモ（判明したら追記）

- Windows: Godot 実行ファイルのパス: （未設定）
- Windows: Blender 実行ファイルのパス: （未設定）
- クラウド: Godot / Blender の導入方法: `bash tools/cloud-setup.sh`（Godot 4.7.2 本体 + Web テンプレートを GitHub リリースから、Blender 4.0.2 を apt から。約1分）
- クラウド: headless での動作確認: `godot --headless --path game --import` → `godot --headless --path game --quit-after 5`
- クラウド: 自動テスト: `godot --headless --path game res://tools/walk_test.tscn`（移動・段差・坂・世界の端・落下の保険）、`res://tools/world_test.tscn`（ワールドの入口）、`res://tools/touch_test.tscn`（スマホのタッチ操作）
- クラウド: スクリーンショット: `bash tools/screenshot.sh build/shot.png [フレーム数] [walk|run|jump] [枚数] [間隔]`（xvfb + Mesa のソフトウェア描画。動作確認済み）。複数枚は `python3 tools/sheet.py build/shot build/sheet.png` で 1 枚に並べる（Pillow が必要: `pip install pillow`）
- クラウド: スクリーンショットの開始位置・向き・Tuning の上書き: `UCHI_POS="x,y,z" UCHI_YAW=-90 UCHI_PITCH=-5 UCHI_TUNING="rain_amount=0.1" bash tools/screenshot.sh ...`（向きは動きの指定がある回だけ効く）、ワールド指定は `WORLD=res://scenes/worlds/gray/gray_world.tscn`
- クラウド: アニメクリップ単体の確認: `bash tools/clip-view.sh build/clip Jump 0.0,0.2,0.4`（指定時刻のポーズを PNG に）
- クラウド: 本キャラのメッシュ生成: `blender --background --python tools/blender/build_traveler.py`（素体 `docs/reference/character/traveler_body.obj` + ポンチョ帽子 `game/assets/traveler_outfit.glb` + 確認用 `traveler_preview.glb`）
- クラウド: 基準画像の実測: `python3 tools/measure_reference.py docs/reference/character/traveler_turnaround_poncho.png`
- クラウド: .glb を四面図で見比べる: `bash tools/model-view.sh build/full res://assets/traveler_preview.glb 1.6` → `python3 tools/sheet.py build/full build/sheet.png`（順は 正面 / 左側面 / 背面 / 右側面。基準画像と同じ並び）
- クラウド: シルエットを基準画像と突き合わせる: `python3 tools/compare_silhouette.py docs/reference/character/traveler_turnaround_poncho.png build/full_1.png`
- クラウド: ターンアラウンドを 1 面ずつに割る（AI 3D 生成に渡す用）: `python3 tools/split_turnaround.py <ターンアラウンド.png> <出力先> <名前>`
- クラウド: AI 3D 生成の出力を寸法に揃える: `blender --background --python tools/blender/normalize_sculpt.py -- <入力> <出力.glb> [身長m] [向きの角度]`
- クラウド: リグ済み .glb にポンチョ・帽子を被せる: `blender --background --python tools/blender/add_outfit.py -- <リグ済み.glb> game/assets/traveler_outfit.glb <出力.glb>`
- クラウド: Mixamo の FBX → .glb: `blender --background --python tools/blender/mixamo_fbx_to_glb.py -- docs/reference/mixamo game/assets/traveler_mixamo.glb`、中身の確認: `godot --headless --path game --script res://tools/inspect_glb.gd -- res://assets/traveler_mixamo.glb`
- クラウド: マントを揺らす骨の差し込み: `blender --background --python tools/blender/add_cloth_bones.py -- game/assets/traveler_mixamo.glb game/assets/traveler_cloth.glb`（ゲームが読むのは `traveler_cloth.glb` のほう）
- Web書き出しのコマンド: `bash tools/export-web.sh` → `build/web/`（約39MB、スレッド無効ビルド）
- ブラウザ確認用の URL（GitHub Pages）: https://axelrodichthys-blip.github.io/uchi-games/ （main への push で `.github/workflows/deploy-pages.yml` が自動配置。Pages の有効化が必要）
