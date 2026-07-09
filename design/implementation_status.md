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
| 11 | DM画像タップで全画面表示 | product.md 3.17節・3.13節 | ✅ 実装済み | `lib/features/messages/conversation_page.dart` (`_MessageBubble`) |
| 12 | DMメッセージは新しい順に下へ表示 | product.md 3.17節 | ✅ 実装済み（既存実装で対応済みを確認） | `lib/features/messages/conversation_page.dart`（`ListView.builder(reverse: true)` + `conversationMessagesProvider`の昇順取得） |
| 13 | DMでの動画アップロード・送信 | product.md 3.17節・system.md 5章 | ✅ 実装済み | `lib/features/messages/messages_controller.dart` (`sendVideoMessage`) + `lib/features/feed/video_upload_controller.dart`（`dmMessageId`対応）+ `supabase/migrations/20260709120000_sync_dm_message_video_ready.sql`（Mux処理完了を`dm_messages.mux_playback_id`へ同期するトリガー） |
| 14 | IntellectをIQスケール（平均100・標準偏差15）で表示 | product.md 3.3節 | ✅ 実装済み | `lib/shared/iq_format.dart`（`intellectIqScore`、パーセンタイル→逆正規累積分布関数による近似変換）を`profile_page.dart`から利用。DBにIQ専用カラムは無いため`intellect_percentile`からクライアント側で都度算出 |
| 15 | バッジ（知能バッジ・TPなど）の余白は横デフォルト・縦なし | product.md 5章 | ✅ 実装済み | `lib/features/feed/intellect_badge.dart` / `lib/features/profile/profile_page.dart` (`_buildBadgeRow`) |
| 16 | メッセージボタン⇔投稿ボタンの配置入れ替え（メッセージをボトムナビ中央、投稿をFeed上部AppBarへ） | product.md 4章 | ✅ 実装済み | `lib/app/main_shell.dart` / `lib/features/feed/feed_page.dart` |
| 17 | 画像・動画は全てタップで全画面表示 | product.md 3.13節 | ✅ 実装済み | 投稿本体・投稿詳細画面（`FullscreenMediaViewer`、既存実装）、コメント添付画像（`comments_sheet.dart`／`post_detail_page.dart`）、DM画像・動画（`conversation_page.dart`）、プロフィールアバター（`profile_page.dart`）を対象に統一 |

## 既知の未対応・今後の課題

- 投稿詳細画面（`post_detail_page.dart`）のコメント投稿フォームは画像・動画添付に未対応（`comments_sheet.dart` にのみ実装）。
- 投稿詳細画面のコメント表示は返信の親子インデント・「返信」ボタンが未実装（フラット一覧のみ）。
- DMの動画メッセージはトランスコード完了まで「処理中」プレースホルダー表示となり、Mux Webhookからの反映を待つ必要がある（リアルタイム購読は`dm_messages`テーブルのUPDATE/INSERTを購読済みのため、トリガー反映後は自動的に再表示される）。
- IQ換算はクライアント側の近似計算であり、DB側に永続化されたIQ値ではない（`intellect_percentile`が更新されるたびに再計算される）。
