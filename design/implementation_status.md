# 実装仕様一覧・実装状況

design/product.md・design/system.md に記載の仕様項目と、現在のFlutterアプリ実装状況を対応付けた一覧。
新規実装・仕様変更のたびに更新すること。

| # | 仕様項目 | 該当design節 | 実装状況 | 実装箇所 |
|---|---|---|---|---|
| 1 | 知能バッジ（上位1%/5%/10%/25%）の表示・余白 | product.md 3.3節 | ✅ 実装済み | `lib/features/feed/intellect_badge.dart` |
| 2 | エンゲージメントボタン（いいね/コメント/リポスト/共有）はアイコンのみ・ラベルなし | product.md 3.12節・5章 | ✅ 実装済み | `lib/features/feed/feed_page.dart` (`_ActionBarButton`) |
| 3 | いいね/コメント/リポスト数は1件以上のみアイコン右側に表示 | product.md 3.12節 | ✅ 実装済み | `lib/features/feed/feed_page.dart` (`_ActionBarButton`) |
| 4 | 投稿・コメント・DMのユーザー名/アバターをタップでプロフィール画面へ遷移 | product.md 3.10節 | ✅ 実装済み | `feed_page.dart`／`comments_sheet.dart`／`post_detail_page.dart`／`discover_page.dart`／`messages_list_page.dart`／`conversation_page.dart` |
| 5 | 一覧画面は相対時間（n分前/n日前）、詳細画面は絶対時刻表示 | product.md 3.12節 | ✅ 実装済み | `lib/shared/time_format.dart`（`relativeTimeLabel` / `absoluteTimeLabel`）を `feed_page.dart` / `discover_page.dart` / `post_detail_page.dart` から利用 |
| 6 | 投稿タップで投稿を親としコメントをスレッド表示する詳細画面（Feed・Discover共通） | product.md 3.12節 | ✅ 実装済み | `lib/features/feed/post_detail_page.dart`（ルート `/posts/:postId`） |
| 7 | プロフィール画面のTPバッジタップでAppSheet詳細表示 | product.md 3.4節・3.10節 | ✅ 実装済み | `lib/features/profile/profile_page.dart` (`_buildBadgeRow`) + `lib/shared/info_bottom_sheet.dart` |
| 8 | プロフィール画面のIntellect/InfluenceタップでAppSheet詳細表示 | product.md 3.3節・3.10節 | ✅ 実装済み | `lib/features/profile/profile_page.dart` (`_buildStatsRow` / `_buildStatItem`) |
| 9 | コメント欄からのメディア添付（画像・動画）付きコメント投稿 | product.md 3.12節 | ✅ 実装済み（ボトムシート版のみ） | `lib/features/feed/comments_sheet.dart`。投稿詳細画面（`post_detail_page.dart`）のコメント投稿はテキストのみの簡易版で、画像・動画添付は未対応 |
| 10 | 投稿詳細画面での返信スレッド（1階層）表示 | product.md 3.12節 | ⚠️ 一部実装 | `post_detail_page.dart` はコメントをフラット表示。返信の階層インデントはボトムシート版（`comments_sheet.dart`）のみ対応 |

## 既知の未対応・今後の課題

- 投稿詳細画面（`post_detail_page.dart`）のコメント投稿フォームは画像・動画添付に未対応（`comments_sheet.dart` にのみ実装）。
- 投稿詳細画面のコメント表示は返信の親子インデント・「返信」ボタンが未実装（フラット一覧のみ）。
