# renga（連歌）

Flutter製のSNSアプリ。バックエンドはSupabase（Postgres / Auth / Storage / Edge Functions）、
プッシュ通知はFirebase Cloud Messaging、動画配信はMux、AI機能（ドメインラベリング・クイズ生成等）は
Gemini APIを利用する。設計の詳細は [design/system.md](design/system.md) / [design/product.md](design/product.md) を参照。

## セットアップ

### 1. 前提ツール

- [Flutter SDK](https://docs.flutter.dev/get-started/install)（Dart SDK `^3.11.3`、`pubspec.yaml` の `environment.sdk` 参照）
- Node.js（`npx supabase` / `npx firebase-tools` をバージョン固定で実行するために使用。グローバルインストール不要）
- [git-crypt](https://github.com/AGWA/git-crypt)（CIシークレット `secrets/ci.yaml` の復号に必要。後述）
- Android Studio / Xcode（各プラットフォームのネイティブビルドに必要な分のみ）

### 2. リポジトリのclone

```sh
git clone <このリポジトリのURL>
cd chatapp-renga
```

### 3. CIシークレット（`secrets/ci.yaml`）のロック解除

Supabase/Google OAuth/Android署名鍵/Play Consoleサービスアカウント等のCIシークレットは
[git-crypt](https://github.com/AGWA/git-crypt)でリポジトリ内に暗号化保存されている。開発を始めるには
先にこれをロック解除する必要がある（手順は下記「CIシークレットへのアクセス設定」を参照）。

ローカル開発でこれらの値そのものが必須なわけではなく（後述の`.env`は各自のSupabase/Firebaseプロジェクトを
使って自分で発行してよい）、CIビルドの内容を確認したい場合や、共有のステージング環境を使う場合に必要になる。

### 4. 依存パッケージの取得

```sh
flutter pub get
```

### 5. 環境変数ファイルの作成

```sh
cp .env.example .env
```

`.env` の各値は自分のSupabase/Firebase/Gemini/Muxプロジェクトの認証情報に置き換える。各サービスの
セットアップ手順（CLIコマンド一式）は [design/system.md — 11. 開発環境・CLI運用](design/system.md#11-開発環境cli運用) に
まとまっている（Supabase CLI / Firebase CLI・FlutterFire CLI / Gemini API / Mux の順）。

主に必要になるもの:

- `SUPABASE_URL` / `SUPABASE_ANON_KEY` — Supabaseプロジェクトのダッシュボードから取得
- `GOOGLE_OAUTH_CLIENT_ID` — Google Sign-In用（Supabase Auth > Providers > Google 有効化時に発行）
- Firebase関連（`FIREBASE_PROJECT_ID` 等）— `flutterfire configure` で自動生成される値を含む
- `GEMINI_API_KEY` — Google AI Studioで発行（Edge Function経由でのみ使用、クライアントには渡さない）
- `MUX_TOKEN_ID` / `MUX_TOKEN_SECRET` — Mux Dashboardで発行
- `ADMOB_*` — 広告ID（開発中はテストIDのままで問題ない）

### 6. コード生成（多言語対応）

```sh
flutter gen-l10n
```

`lib/l10n/gen/` にローカライズ用コードが生成される（`l10n.yaml` 参照。`.gitignore`済みのためclone直後は必須）。

### 7. アプリの起動

```sh
flutter run
```

## Supabaseバックエンドのセットアップ

新規にSupabaseプロジェクトを使う場合は以下の流れになる（詳細は
[design/system.md — 11.2 Supabase CLI](design/system.md#112-supabase-cli) 参照）。

```sh
npx supabase login
npx supabase link --project-ref $SUPABASE_PROJECT_REF
npx supabase db push
npx supabase functions deploy <function-name>
npx supabase gen types dart --linked
```

Edge Function用のシークレット（`GEMINI_API_KEY` 等）は `npx supabase secrets set` で別途登録する。

## CIシークレットへのアクセス設定

CIで使う各種シークレット（Supabase/Google OAuth/Android署名鍵/Play Consoleサービスアカウント等）は`secrets/ci.yaml`にまとめ、[git-crypt](https://github.com/AGWA/git-crypt)でリポジトリ内に暗号化保存している。GitHub Actions上では対称鍵（`GIT_CRYPT_KEY_BASE64` Secret）でアンロックするが、**人間の開発者はGPG鍵ベースでアンロックする**（対称鍵の手動受け渡しは行わない）。

### 新規メンバーのセットアップ手順

1. git-cryptをインストールする（例: WSL/Linuxなら `sudo apt install git-crypt`、macOSなら `brew install git-crypt`）
2. まだGPG鍵を持っていなければ作成する
   ```sh
   gpg --full-generate-key
   ```
3. 自分のGPG鍵IDを確認し、既存メンバー（リポジトリの`git-crypt`鍵管理者）に伝える
   ```sh
   gpg --list-secret-keys --keyid-format LONG
   ```
4. 既存メンバー側で以下を実行し、コミット・pushしてもらう
   ```sh
   git-crypt add-gpg-user --trusted <新規メンバーのGPG鍵ID>
   ```
5. 上記コミットをpullした後、リポジトリ直下で以下を実行するだけでロック解除される（自分のGPG秘密鍵が使われるため、鍵ファイルのやり取りは不要）
   ```sh
   git-crypt unlock
   ```
6. 以後`secrets/ci.yaml`はワーキングツリー上で平文のYAMLとして読み書きでき、コミット時は自動的に再暗号化される。

詳細な運用方針は [design/system.md — シークレット管理方針（git-crypt）](design/system.md) を参照。

## テスト・Lint

```sh
flutter analyze
flutter test
```

## ディレクトリ構成の目安

- `lib/app/` — ルーティング・アプリシェル
- `lib/features/` — 機能別（feed / discover / profile / messages / settings 等）
- `lib/shared/` — 共通ウィジェット・ユーティリティ
- `packages/renga_ui/` — デザインシステム（ローカルパッケージ、Widgetbookでカタログ管理）
- `supabase/` — マイグレーション・Edge Functions
- `design/` — 設計ドキュメント（`system.md` = 技術設計、`product.md` = プロダクト仕様）
- `docs/` — GitHub Pagesで公開する利用規約・プライバシーポリシー・ランディングページ

## 参考リンク

- [Flutter公式ドキュメント](https://docs.flutter.dev/)
- [design/system.md](design/system.md) — システム設計（データモデル・バックエンド構成・CI/CD等）
- [design/product.md](design/product.md) — プロダクト仕様
- [design/implementation_status.md](design/implementation_status.md) — 実装状況の対応表
