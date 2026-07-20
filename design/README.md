# Renga（連歌）設計書

次世代2軸評価型SNS — 設計概念・エコシステム・機能要件定義

設計書は以下の2ファイルに分割している。

- **[product.md](product.md)** — プロダクトコンセプト、エコシステム、機能要件、情報アーキテクチャ、デザインシステム、マネタイズ、Playストアリリース準備、ロードマップ
- **[system.md](system.md)** — データモデル、スコアリングロジック、Supabase/Firebase/Gemini各アーキテクチャ、Flutterアプリ構成、CLI運用、無料枠制約

環境変数（Supabase CLI / Firebase CLI / Gemini API 等）は [.env.example](../.env.example) を参照。

## AI向け設計メモ（`ai/`）

実装前のトークン効率重視の半構造化メモを置く場所。個別機能の設計・不具合修正のメモに加え、
再利用可能な手順書も含む：

- **[ai/testing_playwright_flutter_web.md](ai/testing_playwright_flutter_web.md)** — このFlutter Webアプリを
  Playwrightでシナリオテストする際の手順（アクセシビリティ有効化、テストアカウント作成・メール確認の回避策、
  クリーンアップ等）。

## 関連アセット（仮置き）

- `assets/icon/renga_icon_1024.png` — アプリアイコン（仮）
- `assets/icon/renga_icon_background_1024.png` / `renga_icon_foreground_1024.png` — Android Adaptive Icon用の背景/前景分離版（仮）
- `assets/store/feature_graphic_1024x500.png` — Play Store フィーチャーグラフィック（仮）
- `assets/store/screenshots/*.png` — ストア掲載用スクリーンショットのワイヤーフレーム・モックアップ（仮、実装後に実機キャプチャへ差し替え）

いずれも仮のプレースホルダーであり、実装が進み次第、本物のUIキャプチャ・ブランドデザインに差し替える前提。
