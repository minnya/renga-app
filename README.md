# renga

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## CIシークレット（`secrets/ci.yaml`）へのアクセス設定

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
