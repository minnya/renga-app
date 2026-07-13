# Renga（連歌）設計書 — システム編

技術アーキテクチャ・データモデル・インフラ構成・開発運用。

プロダクト仕様（コンセプト・機能要件・UX・リリース計画）は [product.md](product.md) を参照。

| 項目 | 値 |
|---|---|
| プロジェクト名（Supabase / Firebase共通） | `renga` |
| Android applicationId | `com.minnya.renga` |
| iOS Bundle Identifier | `com.minnya.renga` |
| バックエンド | Supabase（Cloud 無料プラン、リージョン: US） |
| 認証 | メール/パスワード + Google Sign-In |
| モバイル基盤 | Firebase（FCM / Remote Config / Crashlytics / Analytics） |
| AI基盤 | Gemini API |
| 動画基盤 | Mux（動画アップロード・エンコード・HLS配信） |
| 広告 | Google AdMob |
| フロントエンド | Flutter（iOS / Android） |
| コンテンツレーティング方針 | Mature 17+ / 18+ 相当を想定（論破・対立煽り要素のため） |

環境変数の一覧・設定方法は [.env.example](../.env.example) を参照。

---

## 目次

1. [データモデル（Supabase / Postgres）](#1-データモデルsupabase--postgres)
2. [スコアリングロジック（Influence / Intellect）](#2-スコアリングロジックinfluence--intellect)
3. [バックエンド構成（Supabase各機能の使い分け）](#3-バックエンド構成supabase各機能の使い分け)
4. [Firebase連携アーキテクチャ](#4-firebase連携アーキテクチャ)
5. [Mux動画アーキテクチャ](#5-mux動画アーキテクチャ)
6. [Gemini AI活用アーキテクチャ](#6-gemini-ai活用アーキテクチャ)
7. [デマ撲滅フローと3ストライク実装](#7-デマ撲滅フローと3ストライク実装)
8. [AIアシスト対策・不正検知](#8-aiアシスト対策不正検知)
9. [Flutterアプリ構成（アーキテクチャ）](#9-flutterアプリ構成アーキテクチャ)
10. [マネタイズ（AdMob）実装](#10-マネタイズadmob実装)
11. [開発環境・CLI運用](#11-開発環境cli運用)
12. [無料枠を前提とした制約とスケーリング方針](#12-無料枠を前提とした制約とスケーリング方針)
13. [コンテンツモデレーション・Trust & Safety](#13-コンテンツモデレーショントrust--safety)
14. [運用体制・コスト概算](#14-運用体制コスト概算)

---

## 1. データモデル（Supabase / Postgres）

RLS（Row Level Security）を全テーブルで有効化する前提。

```sql
-- ユーザープロフィール（auth.usersと1:1）
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text,
  avatar_url text,
  bio text,
  website_url text, -- product.md 3.10節「プロフィール詳細設定」の外部リンク1件
  location text, -- product.md 3.10節。自由入力、位置情報の実測はしない
  locale text not null default 'en', -- ユーザーの表示言語設定 (en | ja)
  influence_score numeric not null default 0,
  influence_percentile numeric not null default 0,
  intellect_score numeric not null default 0,
  intellect_percentile numeric not null default 0,
  tp_balance numeric not null default 0,
  strike_count int not null default 0,
  strike_expires_at timestamptz,
  is_permanently_banned boolean not null default false,
  created_at timestamptz not null default now()
);

-- 投稿
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id),
  body text not null,
  media_type text not null default 'text', -- text | image | video | youtube_embed
  media_urls text[], -- 画像URL（Supabase Storage）。動画はvideosテーブルで管理
  external_video_url text, -- YouTube等の外部動画URL（原文のまま保持）
  external_video_provider text, -- youtube 等
  external_video_id text, -- YouTube動画ID（埋め込み再生用に抽出したもの）
  post_type text not null default 'normal', -- normal | staked（旧 battle_challenge は真偽投票への一本化に伴い廃止）
  context text not null default 'feed', -- feed | discover。投稿がどの画面のCreate権限で作られたか（2.1節）。Discoverでの新規投稿はcontext='discover'
  staked_tp numeric not null default 0,
  domain_labels text[] not null default '{}', -- AIが自動付与（3.5節「サイレント・ドメイン・マッピング」、実装済み）
  logic_verdict text not null default 'unverified', -- unverified | endorsed。旧flagged_brokenは警告バッジ廃止に伴い削除（product.md 3.6節）
  truth_verdict text, -- null（未リクエスト/未確定）| true | false。真偽審判リクエストの確定結果（3.4節・下記truth_judgment_requests参照）
  reach_score numeric not null default 0, -- 拡散スコア（モデレーションflagged時に0へ、13章）
  quoted_post_id uuid references public.posts(id), -- product.md 3.12節「引用リポスト」。引用元投稿（nullなら通常投稿）
  created_at timestamptz not null default now()
);

-- `quoted_post_id`はposts自身への自己参照FK。クライアント側でPostgRESTのネストselectにより
-- 引用元投稿を埋め込む際、`quoted_post:posts!quoted_post_id(...)`という書き方だと自己結合の
-- 方向が曖昧になり、逆方向（「このポストを引用している側」）に解決されてしまう場合があるため、
-- 必ずFKカラム名を直接指定する`quoted_post:quoted_post_id(...)`という書き方を使うこと
-- （`lib/features/feed/feed_controller.dart`参照）。

-- 動画（Mux連携）。1投稿につき最大1本、またはコメント/返信につき最大1本を想定
create table public.videos (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade, -- コメント添付動画の場合はnull
  comment_id uuid references public.comments(id) on delete cascade, -- 投稿添付動画の場合はnull（post_id/comment_idのどちらか一方必須）
  uploader_id uuid not null references public.profiles(id),
  mux_upload_id text, -- Mux Direct Upload ID（アップロード開始直後に採番）
  mux_asset_id text, -- Mux処理完了後に確定
  mux_playback_id text, -- HLS配信用ID（https://stream.mux.com/{id}.m3u8）
  status text not null default 'pending', -- pending | uploading | processing | ready | errored
  duration_seconds numeric,
  thumbnail_url text, -- https://image.mux.com/{playback_id}/thumbnail.jpg
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- リポスト（検証状態に応じて警告を出す）
create table public.reposts (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id),
  user_id uuid not null references public.profiles(id),
  acknowledged_warning boolean not null default false,
  created_at timestamptz not null default now(),
  unique(post_id, user_id)
);
-- RLS: select全公開 + insert-own + delete-own（un-repost用）。3.12節「基本エンゲージメント機能」参照。
-- 「引用リポスト（コメント付き再共有）」は本テーブルではなく、`posts.quoted_post_id`を
-- セットした通常の`posts` insertとして表現する（X同様、単純リポストと引用リポストは別経路）。
-- 単純リポスト（`reposts` insert、引用なし）と引用リポスト（`posts.quoted_post_id`）は
-- 独立に成立し、UI上はリポストアイコンタップ時のボトムシートでどちらかを選択する
-- （3.12節）。

-- Feed → Discoverキュレーション（product.md 3.5節）。Feedの既存投稿をDiscoverにも表示させる
-- 中間テーブル。元のFeed投稿はfeedのまま残り（削除・移動しない）、Discover側にも同じ投稿が
-- 参照として表示される（Xのリポストと同様の「両方に出る」挙動。posts.contextは変更しない）。
create table public.discover_promotions (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  promoted_by uuid not null references public.profiles(id), -- Create権限保持者（上位25%以上）のみ
  tp_cost numeric not null, -- 3.4節と同水準の高コストTP消費（tp_transactionsに'discover_promotion'として記録）
  created_at timestamptz not null default now(),
  unique (post_id) -- 同一投稿の多重昇格は禁止（重複引き上げ防止）
);
-- RLS: select全公開。insertは`Create`権限保持者のみ、かつpost.contextが'feed'の場合のみ許可
-- （すでにdiscover文脈の投稿を重ねて昇格させる意味がないため）。
-- 「目利き報酬」（product.md 3.5節）は、promoted_byの投稿がDiscoverで一定の反響
-- （例: 真偽投票のtrue確定、または一定いいね数）を得た場合にEdge Functionがtp_transactionsへ
-- 報酬レコードを追加する形で実現する（7章に判定条件を定義）。

-- いいね（基本エンゲージメント機能。3.12節）
create table public.likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(post_id, user_id)
);
-- RLS: select全公開 + insert-own + delete-own（un-like用）。

-- コメント（基本エンゲージメント機能。3.12節）
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  parent_comment_id uuid references public.comments(id) on delete cascade, -- 返信スレッド用（1階層）。nullはトップレベルコメント
  body text not null,
  media_urls text[], -- 返信・コメントへの画像添付（複数可、3.12節）
  external_video_url text, -- コメントへの動画添付（Mux連携、videosテーブルのpost_idの代わりにcomment_idも参照可能にする想定）
  created_at timestamptz not null default now()
);
-- RLS: select全公開 + insert-own + delete-own（自分のコメント削除のみ）。
-- 補足: 動画添付コメントはvideosテーブルのFK制約を`post_id`固定ではなくpolymorphicに近い形へ拡張するか、
--       comment_id用の別カラム（例: videos.comment_id、post_idはnullable化）を追加して対応する。

-- Endorse（お墨付き）
create table public.endorsements (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id),
  endorser_id uuid not null references public.profiles(id),
  domain text, -- 専門家Endorseの場合のドメイン
  kind text not null, -- domain_endorse | logic_endorse (バックアップ昇格)
  created_at timestamptz not null default now(),
  unique(post_id, endorser_id, kind)
);

-- 真偽審判リクエスト（product.md 3.4節。旧battles/battle_bets/logic_verdictsのフェーズ制judge投票を廃止し、
-- 「Create権限保持者によるオプトイン型の真偽投票」1本に統合した後継テーブル）。
-- 投稿には既定で真偽投票UIを一切表示せず、`Create`権限保持者（上位25%以上）がこのリクエストを
-- 起票した投稿のみ、真偽投票（truth_votes）が可能になる（product.md 2.1節・3.4節）。
-- Feed/Discover双方のcontextの投稿を対象にできる（旧設計ではcontext='discover'限定だったが解禁した）。
-- 投票参加資格はさらに「投稿者本人と同格以上の知能階層」に絞られるが、リクエスト起票者本人
-- （requested_by）はこの制限を免除され、常に自分が起票した投票に参加できる（下記truth_votes参照）。
create table public.truth_judgment_requests (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  requested_by uuid not null references public.profiles(id),
  author_intellect_percentile_snapshot numeric not null, -- リクエスト起票時点の投稿者intellect_percentileを固定保存。
    -- 投票参加資格「投稿者本人と同格以上（percentile <= この値）」の判定基準はこのスナップショットを使い、
    -- 投票期間中にintellect_percentileが定期再計算（30分毎）で変動しても基準がぶれないようにする
  status text not null default 'voting', -- voting | resolved | invalid
  resolved_verdict boolean, -- true=真が多数, false=偽が多数, null=未確定/無効
  true_vote_count int not null default 0, -- 締切時の集計値（非正規化。Edge Function `resolve_truth_judgment`が確定時に書き込む）
  false_vote_count int not null default 0,
  quorum_threshold int not null default 10, -- 締切時にtrue+false投票数がこれ未満なら invalid（無効・全額返還）。Remote Config `truth_judgment_quorum` から起票時にコピー
  opens_at timestamptz not null default now(),
  closes_at timestamptz not null, -- opens_at + 24時間（Remote Config `truth_judgment_window_hours`）。pg_cronがこの時刻到達で自動締切
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  unique (post_id) -- 1投稿につきリクエストは1回のみ（再リクエスト不可。誤操作防止）
);
-- RLS: select全公開。insertは`Create`権限保持者（intellect_percentile <= 25 相当、RLS内で`profiles`参照）
-- のみ許可（対象postのcontextは問わない、Feed/Discover双方許可）。update/deleteはEdge Function
-- （service role）のみ。

-- 真偽投票（投票権チケット消費、product.md 3.4.2節〜3.4.3節）。
-- 直接TPを賭け合うP2Pの賭博構造を避けるため、投票はTPではなく「投票権チケット」を1枚消費する
-- （チケット自体はuser_assets.ticket_countで管理し、tp_transactionsにはチケット消費の記録を残さない）。
create table public.truth_votes (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.truth_judgment_requests(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  verdict boolean not null, -- true=本当, false=嘘
  voter_tier text not null, -- 'top5' | 'top25'（投票時点のintellect_percentileから判定し、product.md 3.4.4節の2階建てメーター集計に使う）
  payout_tp numeric, -- 確定後に反映。的中: product.md 3.4.3節の数理式に基づく山分けボーナスをtp_transactionsで別途新規発行（原資分離）。外れ: 0（チケットは全損・返還なし）。無効: チケットのみ返還
  created_at timestamptz not null default now(),
  unique (request_id, user_id) -- 1リクエストにつき1ユーザー1票（撤回不可、変更不可）
);
-- RLS: select全公開（ただし4章のブラインド投票フェーズ中は、クライアント側で自分の投票以外の
--   verdict内訳をUI上マスクし、「総票数」のみ見せる。締切/自分の投票完了後にアンロックする）。
--   insertは以下すべてを満たす場合のみ許可（cast_truth_vote RPC内で検証）:
--   (1) is_top_intellect_tier(auth.uid())（Create権限、上位25%以上）
--   (2) profiles.intellect_percentile <= truth_judgment_requests.author_intellect_percentile_snapshot
--       （投稿者本人と同格以上の知能階層のみ投票可、product.md 3.4節）。ただし
--       auth.uid() = truth_judgment_requests.requested_by（リクエスト起票者本人）の場合はこの
--       階層チェックを免除する（起票者本人は常に自分の起票した投票に参加できる）
--   (3) 対象request.status='voting'かつcloses_at未到達
--   (4) auth.uid() <> 対象postのauthor_id（投稿者本人による自己投票（自演）を禁止。利益相反防止）
--   (5) user_assets.ticket_count > 0（チケット保有）— insert時のRPC（cast_truth_vote）内で
--       ticket_countを-1するトランザクションと不可分に実行する
-- update/deleteは不可（撤回不可の要件を素朴にDBレベルでも担保する）。

-- ユーザー資産（TP残高・投票権チケット枚数を一元管理、product.md 3.4.5節）。
-- チケット仲介方式の要。真偽投票時はticket_countを-1するだけで完結させ、ユーザー間のTP移転を発生させない。
create table public.user_assets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  tp_balance numeric not null default 0, -- profiles.tp_balanceは段階的にこちらへ一本化（過渡期は同期）
  ticket_count int not null default 0,
  last_daily_ticket_granted_at date, -- Top 25%/Top 5%への「毎日無料チケット3枚」デイリーボーナスの多重付与防止（UTC日付ベース）
  updated_at timestamptz not null default now()
);
-- RLS: selectは自分の行のみ。insert/updateはEdge Function（service role）のみ。

-- ドメイン別専門スコア（product.md 3.4.1節「投稿しない隠れた賢者」の自動ドメイン抽出ロジック）。
create table public.domain_scores (
  user_id uuid not null references public.profiles(id),
  domain text not null,
  score numeric not null default 0,
  badge_tier text, -- null | expert | master
  updated_at timestamptz not null default now(),
  primary key (user_id, domain)
);
-- 上記`domain_scores`は3.5節のEndorse実績由来の専門スコア。真偽投票の的中実績から逆算する
-- 「投稿しない賢者」向けの加点は`user_domain_scores`（下記、投票ログ由来）に分離して二重計上を避ける。
create table public.user_domain_scores (
  user_id uuid not null references public.profiles(id) on delete cascade,
  domain text not null,
  correct_vote_streak int not null default 0, -- そのドメインの投稿に対する真偽投票で、多数決（正解側）と一致し続けている連勝数
  correct_vote_total int not null default 0,
  promoted_to_domain_expert boolean not null default false, -- 一定基準（Remote Config）超過でtrueにし、そのドメインではTop 5%相当の重み付けを与える
  updated_at timestamptz not null default now(),
  primary key (user_id, domain)
);
-- 締切精算（resolve_truth_judgments）の一部として、的中投票者について対象投稿のドメインラベル
-- （posts.domain_labels）ごとにcorrect_vote_streakを加算し、閾値到達でpromoted_to_domain_expertをtrueにする。

-- Influence/Intellectの日次スナップショット（プロフィール画面の推移グラフ・前日比表示用、2章参照）。
-- `recalculate_intellect_scores`/`recalculate_influence_scores` で更新された profiles の値を
-- 日次バッチ（`snapshot_daily_scores`）でコピーする、いわゆるhistoryテーブル。
-- ユーザーごと・日付ごとに1行（`unique(user_id, snapshot_date)`）とし、同日に複数回実行されても
-- 上書き（upsert）されるようにする。
create table public.user_score_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  snapshot_date date not null default current_date,
  intellect_score numeric not null default 0,
  intellect_percentile numeric not null default 0,
  influence_score numeric not null default 0,
  influence_percentile numeric not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, snapshot_date)
);

-- 全ユーザー横断の平均値（プロフィール画面の「平均より+15」等の比較表示用）を保持する
-- シングルトンテーブル。都度全ユーザーを集計するとDB負荷が大きいため、
-- `recalculate_score_stats()` バッチでキャッシュする（12章の考え方に準拠）。
create table public.score_stats (
  id boolean primary key default true,
  avg_intellect_iq numeric not null default 100, -- 全ユーザーのIQ換算値(iq_format.dart相当)の平均
  avg_influence_score numeric not null default 0,
  avg_influence_percentile numeric not null default 50,
  computed_at timestamptz not null default now(),
  constraint score_stats_singleton check (id)
);

-- IQテスト問題プール（Geminiによる自動生成・マルチエージェント検証を経て投入される。詳細は6章）
create table public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  kind text not null, -- onboarding | daily | lock_quiz
  question_type text not null, -- logic | geometry | current_events
  locale text not null default 'en', -- en | ja
  payload jsonb not null, -- 問題文・選択肢・図形データ等
  correct_answer text not null,
  difficulty int not null default 1,
  time_limit_seconds int not null default 15,
  is_active boolean not null default true,
  generated_by text not null default 'gemini', -- gemini | human
  generation_run_id uuid references public.quiz_generation_runs(id),
  validation_status text not null default 'pending', -- pending | approved | rejected | human_review
  solver_agreement_rate numeric, -- マルチエージェント検証でのソルバー一致率(0-1)
  validator_notes text,
  created_at timestamptz not null default now()
);

-- クイズ自動生成バッチの実行ログ（生成AI・複数ソルバーAI・検証AIのパイプライン単位）
create table public.quiz_generation_runs (
  id uuid primary key default gen_random_uuid(),
  question_type text not null,
  locale text not null default 'en',
  target_difficulty int not null,
  generator_model text not null, -- 例: gemini-1.5-flash
  solver_models text[] not null, -- 複数ソルバーAIのモデル名配列
  validator_model text not null,
  candidates_generated int not null default 0,
  candidates_approved int not null default 0,
  status text not null default 'running', -- running | completed | failed
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

-- ユーザー回答ログ（動的スコア収束の元データ）
create table public.quiz_responses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  question_id uuid not null references public.quiz_questions(id),
  is_correct boolean not null,
  response_time_ms int not null,
  answered_at timestamptz not null default now()
);

-- 旧「ロジック破綻認定（ジャッジ投票）」テーブル（logic_verdicts）は、product.md 3.4節/3.6節の
-- 見直しにより truth_judgment_requests / truth_votes（上記）へ統合・廃止した。
-- ストライク発火は下記の通り truth_judgment_requests の確定結果を直接参照する。

-- ストライク履歴
create table public.strikes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  strike_number int not null, -- 1,2,3
  reason_request_id uuid references public.truth_judgment_requests(id), -- 真偽投票で「偽」確定したリクエスト（7章参照）
  created_at timestamptz not null default now()
);

-- 異議申し立て
create table public.appeals (
  id uuid primary key default gen_random_uuid(),
  target_type text not null, -- truth_judgment | strike
  target_id uuid not null,
  user_id uuid not null references public.profiles(id),
  status text not null default 'pending', -- pending | approved | rejected
  created_at timestamptz not null default now()
);

-- TP元帳（全てのTP増減を記録する監査テーブル。product.md 3.4.1節）。
-- `profiles.tp_balance` はこのテーブルの累積値のキャッシュとして扱い、Edge Function側で
-- 「tp_transactions insert + profiles.tp_balance update」を単一トランザクション（RPC）内で
-- 必ず対にして実行する（キャッシュと元帳の不整合を防ぐ）。
create table public.tp_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  amount numeric not null, -- 正=獲得、負=消費/没収
  reason text not null,
  -- 例: quiz_daily_reward | quiz_onboarding_reward | truth_vote_ticket_purchase |
  --     truth_vote_payout（山分けボーナス、新規発行） | staked_post | discover_post_cost |
  --     discover_promotion_cost | discover_scout_reward | comment_slot_auction |
  --     cosmetic_purchase | tp_purchase（課金）
  -- 備考: 投票権チケットの消費・返還・失効自体はTP増減を伴わないため、tp_transactionsには
  --     記録しない（user_assets.ticket_countの増減のみで完結させる。product.md 3.4.5節）。
  ref_type text, -- post | truth_judgment_request | truth_vote | discover_promotion 等（監査時の参照用）
  ref_id uuid,
  balance_after numeric not null, -- 記帳直後の残高スナップショット（監査・不正検知の突合を容易にする）
  created_at timestamptz not null default now()
);
-- RLS: selectは自分の行のみ（他人のTP取引履歴は非公開）。insert/update/deleteはEdge Function（service role）のみ。
-- インデックス: (user_id, created_at desc) — プロフィール画面等での履歴取得用。

-- FCMデバイストークン（プッシュ通知送信用。Firebase Cloud Messaging連携）
create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  fcm_token text not null,
  platform text not null, -- ios | android
  app_version text,
  updated_at timestamptz not null default now(),
  unique(user_id, fcm_token)
);

-- 通報（Trust & Safety。ロジック破綻とは別レイヤーの安全性モデレーション。詳細は13章）
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id),
  target_type text not null, -- post | video | profile
  target_id uuid not null,
  reason text not null, -- violence | sexual_content | harassment | csam | spam | other
  detail text,
  status text not null default 'pending', -- pending | actioned | dismissed
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

-- AIモデレーション判定ログ（画像/動画/テキストの自動チェック結果）
create table public.moderation_checks (
  id uuid primary key default gen_random_uuid(),
  target_type text not null, -- post | video
  target_id uuid not null,
  checked_content text not null, -- text | image | video_thumbnail
  model text not null, -- 例: gemini-1.5-flash
  verdict text not null, -- approved | flagged | human_review
  categories text[] not null default '{}', -- violence | sexual_content | harassment | hate_speech 等
  confidence numeric,
  created_at timestamptz not null default now()
);
```

補足:

- パーセンタイル（`influence_percentile`, `intellect_percentile`）は定期バッチ（Supabase Scheduled Function / pg_cron）で再計算し、`profiles` に反映するキャッシュ列とする（都度全体集計は無料枠のDB負荷的に不可）。全ユーザー平均値のキャッシュ（`score_stats`）と日次推移（`user_score_history`）も同様に定期バッチで生成する（2章「平均値・日次推移」参照）。
- `reach_score` を0にすることでフィード表示ロジック（Edge FunctionまたはPostgRESTのview）が自動的にそのポストを除外する。
- `quiz_questions.locale` によりユーザーの `profiles.locale` に応じた出題切り替えを行う。日本語ローカライズが手薄な初期段階では英語問題を出しフォールバックする設計とする。
- `likes` / `comments` / `reposts` の件数はフィード取得時にPostgRESTの集計embed（例: `select=*,likes(count),comments(count),reposts(count)`）で都度取得する。MVP規模（無料枠、投稿数少数）ではキャッシュ列を持たず都度集計で十分と判断し、将来的に投稿数が増えた場合は`posts`テーブルへの非正規化カウンタ列導入を検討する（[12章](#12-無料枠を前提とした制約とスケーリング方針)の考え方に準拠）。
- **上位ユーザー（`Create`権限、product.md 2.1節）判定の共通関数**: 「Discoverへの新規投稿」「真偽審判リクエストの起票」「真偽投票」「Discoverキュレーション（`discover_promotions` insert）」は、いずれも同一の条件（`profiles.intellect_percentile <= 25`）で権限判定する。RLSポリシー内で毎回同じ条件式を書かず、`public.is_top_intellect_tier(uid uuid) returns boolean`（`security definer`関数、`profiles.intellect_percentile`を参照）を共通ヘルパーとして定義し、各テーブルのRLSポリシーから呼び出す。

---

## 2. スコアリングロジック（Influence / Intellect）

### Influence Score

- フォロワー数、リポスト数、インプレッション数を重み付き合成（例: `log(followers+1)*0.4 + log(reposts+1)*0.4 + log(impressions+1)*0.2`）。
- 定期バッチで再計算し、全ユーザー中のパーセンタイル順位に変換。

### Intellect Score

- 基礎値: `quiz_responses` の正答率・回答速度から算出（速く正確なほど高評価、ただし極端に速い＝AI/チート疑惑としてフラグ）。
- 加点: 真偽投票（`truth_votes`）で的中（多数決側に投票）した回数、専門家Endorse獲得、上位層からのlogic_endorse。
- 減点: 自分の投稿が真偽投票で「偽」確定（`truth_judgment_requests.resolved_verdict = false`）した回数・重み。
- 同様にパーセンタイルへ変換し `intellect_percentile` に反映。バッジ表示条件はこの値を参照。

### 動的収束モデル（将来拡張）

初期はシンプルな加重平均から開始し、将来的にIRT（項目反応理論）ベースのベイズ推定モデルへ移行できるよう、`quiz_responses` に生ログを全て保持する設計とする（Edge Function内のロジックを差し替えるだけで移行可能）。

### 平均値・日次推移（プロフィール画面の比較表示）

- `profiles.intellect_percentile` / `influence_percentile` は「値が小さいほど上位」のパーセンタイルであり、母集団平均は理論上50付近になるが、クイズ未回答ユーザーが`intellect_score=0`に集中する等の理由で実際の分布には偏りが生じる。そのため平均値は都度計算せず、`recalculate_score_stats()`（`public.inverse_normal_cdf`によるIQ換算を内部で使用、`lib/shared/iq_format.dart`のAcklamの近似式のSQL移植）で全ユーザーの平均IQ・平均Influenceパーセンタイルを算出し `score_stats`（シングルトン行）へキャッシュする。
  - Intellect: 自分のIQ（`intellect_percentile`をIQ換算した値）と `score_stats.avg_intellect_iq` の差分を「平均より+N」として表示する。
  - Influence: 自分の `influence_percentile` と `score_stats.avg_influence_percentile` の差分（ポイント差）を「平均より+N」として表示する。
- 日次推移は `snapshot_daily_scores()` が `profiles` の現在値を `user_score_history` に1日1行（`unique(user_id, snapshot_date)`のupsert）で記録する。プロフィール画面の前日比は直近の`user_score_history`行と現在値の差分から算出する。
- `recalculate_intellect_scores()` / `recalculate_influence_scores()` は既存どおり30分おきのpg_cronで実行し続け、`recalculate_score_stats()` と `snapshot_daily_scores()` は1日1回のpg_cronジョブ（`daily-score-snapshot`）として追加する（3章）。
- プロフィール画面ではIQ表示部分・Influence表示部分をタップすると、`user_score_history`を時系列に取得し折れ線グラフ（`fl_chart`）で推移を表示するボトムシートを開く。グラフには`score_stats`から取得した平均値を基準線（水平線）として重ねる（product.md 3.10節）。

---

## 3. バックエンド構成（Supabase各機能の使い分け）

| Supabase機能 | 用途 |
|---|---|
| **Auth** | メール/パスワード + Google Sign-In（OAuth）、`auth.users` と `profiles` の1:1連携（トリガーで自動作成）。`profiles.profile_completed` でGoogle新規登録直後の未入力状態を判定し、未完了ユーザーは`/complete-profile`へ強制遷移させる（後述） |
| **Postgres + RLS** | 全データの永続化。RLSで「本人のみ更新可」「公開読み取り可」等を制御 |
| **Edge Functions** | (1) AIドメインラベリング（Gemini API呼び出し） (2) クイズ自動生成・マルチエージェント検証パイプライン（6章） (3) スコア再計算バッチ (4) 真偽審判リクエスト起票・投票・締切精算（`request_truth_judgment` / `cast_truth_vote` / `resolve_truth_judgment`、7章） (5) ストライク判定・実行 (6) 不正検知 (7) FCMプッシュ通知送信 (8) Mux Direct Upload URL発行・Mux Webhook受信（5章） (9) UGCモデレーション（画像/動画/テキストの自動チェック、13章） |
| **pg_cron / Scheduled Functions** | パーセンタイル再計算（30分毎）、平均値キャッシュ再計算・日次スコアスナップショット記録（`recalculate_score_stats()`/`snapshot_daily_scores()`、1日1回）、真偽審判リクエストの締切精算（`closes_at` 到達時に`resolve_truth_judgment`を実行、5〜10分毎のポーリング）、デイリーミッションのリセット、クイズ問題プールの自動補充 |
| **Storage** | 投稿メディア（画像/動画）、アバター画像 |
| **Realtime** | Discover投稿の真偽投票数の**アプリ起動中のライブ更新**（`truth_judgment_requests`のtrue_vote_count/false_vote_countをRealtimeで購読。インアプリのみ、バックグラウンド通知はFirebase FCMが担当） |
| **PostgREST (自動API)** | Flutterからの標準CRUD |

Edge Functionsから呼び出すAI機能（ドメインラベリング、クイズ自動生成・検証、AIチート検知の一部の文章解析）は**Gemini API（Google AI Studio / Vertex AI経由）**を採用する。APIキーはSupabaseのFunction Secretsで管理し、クライアントに一切露出させない。

Edge Functionsは「イベント発生時（Endorse獲得、バッジ実績解除、ストライク、真偽審判リクエスト確定等）にFirebase Cloud Messaging (FCM) HTTP v1 APIを呼び出してプッシュ通知を送信する」役割も担う（詳細は4章）。

---

## 4. Firebase連携アーキテクチャ

バックエンドはSupabaseに一本化しつつ、モバイルOS標準の通知・配信基盤としてFirebaseの以下の機能を併用する。
**Firebaseは認証・DBとしては使わない**（Auth/Postgres/StorageはSupabaseに統一し二重管理を避ける）。

| Firebase機能 | 用途 |
|---|---|
| **Cloud Messaging (FCM)** | プッシュ通知の配信基盤。Endorse獲得・バッジ実績解除・真偽審判リクエスト確定・ストライク警告・デイリーミッションのリマインド等を配信 |
| **Remote Config** | クイズの出題難易度パラメータ、ストライク閾値、レイヤーフィルターのデフォルト値、真偽投票の締切時間・クォーラム閾値、機能フラグ（専門家発掘機能・広告表示などのON/OFF）をアプリ更新なしで調整するための設定配信 |
| **Crashlytics** | クラッシュ・非致命的エラーの収集 |
| **Analytics** | 画面遷移・主要アクション（投稿、Endorse、真偽審判リクエスト、真偽投票）のイベント計測 |
| **App Distribution**（任意） | TestFlight/Google Play内部テスト前の社内配布に利用可 |

### 通知アーキテクチャ

```
[Supabase Edge Function]
   ├─ イベント検知（Endorse insert / strike insert / truth_judgment_requests resolved 等のトリガー）
   ├─ 対象ユーザーの device_tokens を profiles経由で取得
   └─ Firebase Admin SDK (Node/Deno) 経由で FCM HTTP v1 API へ送信
        └─ [端末] Flutterアプリ（firebase_messaging）が受信・表示・タップ時ディープリンク
```

- Edge Function内でFirebase Admin SDKの秘密鍵（サービスアカウントJSON）をSupabase Function Secretsとして保持し、FCM送信専用に利用する。
- Flutter側は `firebase_messaging` パッケージでトークンを取得し、ログイン時・トークンリフレッシュ時に `device_tokens` へupsertする。
- 通知タップ時のディープリンクはgo_routerのルートパスをペイロードに含めて解決する。
- 通知本文はユーザーの `profiles.locale`（既定: en）に応じて英語/日本語を出し分ける。

### Remote Configの利用方針

- キー例: `daily_quiz_count`, `lock_quiz_question_count`, `strike_thresholds`（例: `[1,3,5]`、7章）, `truth_judgment_window_hours`（例: 24）, `truth_judgment_quorum`（例: 10）, `ticket_tp_price`（例: 100）, `ticket_bulk_discount_tiers`, `daily_free_ticket_count`（例: 3、Top 25%/Top 5%向け）, `domain_expert_vote_streak_threshold`（product.md 3.4.1節）, `default_layer_filter`, `feature_expert_discovery_enabled`, `ads_enabled`。
- Remote Configの値は「クライアント側の表示・UX調整」に限定し、金銭・スコアに関わる**信頼できる計算はEdge Function/DB側に必ず二重で持たせる**（クライアント改ざん対策）。
- Firebase CLIでテンプレート（`remoteconfig.template.json`）をバージョン管理し、`firebase deploy --only remoteconfig` でデプロイする。

---

## 5. Mux動画アーキテクチャ

Twitter的に動画を手軽に共有できることを実現するため、動画のアップロード・エンコード・配信は
**Mux（Mux Video）**に委譲する。Supabase Storageには動画本体を置かず、DB/帯域の無料枠を消費しない設計とする。

> **Muxの料金体系について**: Muxには3つのプランがあり、開発初期は **Free** プランで開始し、規模拡大に応じて **Pay as you go** または **Pre-pay** へ切り替える方針とする（プラン切り替えはMux Dashboard上の請求設定変更のみで完結し、API/実装コードの変更は不要）。
>
> | プラン | 内容 |
> |---|---|
> | **Free**（開始プラン） | クレジットカード登録不要。月間配信100,000分まで無料、**動画保存本数は最大10本まで**、オンデマンド配信のみ（ライブ配信不可） |
> | **Pay as you go** | 使用量ベースの従量課金。月間配信100,000分は引き続き無料相当（クレジット消費前）、**保存本数の上限なし**、オンデマンド+ライブ配信対応、月額$20分の利用クレジット付与、Mux Robots（AI機能）利用可 |
> | **Pre-pay** | 前払いクレジット制。Launch: $20/月で$100分のクレジット、Scale: $500/月で$1,000分のクレジット。月間配信100,000分を含み、クレジット消費後は従量課金に移行 |
>
> **Freeプランの「保存本数10本まで」という制約はMVP開発上の実質的なボトルネックになる**ため、`videos` テーブルで `status='ready'` の件数を監視し、上限に近づいたら（a）検証用の不要動画を削除する、または（b）Mux DashboardでPay as you go/Pre-payへアップグレードする、のいずれかを運用手順として定めておく（[12章](#12-無料枠を前提とした制約とスケーリング方針)）。本番リリース（Play Store公開）のタイミングでは実質的にPay as you goへの切り替えが前提となる。

### 5.1 動画アップロードフロー（Direct Upload）

動画バイナリをSupabase Edge Functionやクライアントのサーバー経由で中継しない
（**Mux Direct Upload**を使い、クライアントからMuxへ直接PUTする）ことで、帯域コストと実装の複雑さを最小化する。

```
[Flutterアプリ: Compose画面で動画を選択]
   │
   ├─ 1. Supabase Edge Function `create_mux_upload` を呼び出す
   │      └─ Edge FunctionがMux API (`POST /video/v1/uploads`) を呼び、
   │         アップロード用の署名付きURLと upload_id を発行
   │
   ├─ 2. クライアントが受け取ったURLへ動画ファイルを直接PUTアップロード
   │      └─ 同時に `videos` テーブルへ `status='uploading'`, `mux_upload_id` でレコード作成
   │
   ├─ 3. Mux側でアップロード完了 → トランスコード（アダプティブビットレートのHLS生成）
   │
   └─ 4. Mux Webhook `video.asset.ready`（または `video.upload.asset_created` 等）を
          Supabase Edge Function `mux_webhook` が受信
          └─ 署名（Mux Webhook Signing Secret）を検証したうえで
             `videos.mux_asset_id` / `mux_playback_id` / `duration_seconds` / `thumbnail_url` を更新し
             `status='ready'` にする。エラー時は `status='errored'` + `error_message` を記録。
```

- `mux_webhook` Edge FunctionはインターネットからアクセスできるSupabaseの公開URLとして発行し、そのURLをMuxダッシュボードのWebhook設定に登録する。
- 処理完了までにタイムラグが生じるため、処理中はプレースホルダーサムネイル＋「処理中」表示をフィードに出す。処理完了時にFCMで軽い通知（任意）を出すことも検討可能。

### 5.2 再生・サムネイル

- 再生: Flutterの `video_player`（+ 必要に応じ `chewie` でUIラップ）でHLS URL `https://stream.mux.com/{playback_id}.m3u8` を直接再生する（Mux専用SDKへの依存を避け、標準的なHLS再生で完結させる）。
- サムネイル: `https://image.mux.com/{playback_id}/thumbnail.jpg` をフィードのプレビュー画像として使用。
- **プリロード**: フィード一覧の`ListView`は`cacheExtent`を画面サイズの2倍に設定し、実際に画面内に表示される前（スクロールで画面2枚分手前の位置に入った時点）で写真・動画のロードを開始する。動画の自動再生・一時停止は引き続き`VisibilityDetector`による実際の可視判定（可視率60%超）でのみ制御し、プリロードのタイミングとは分離する。
- **キャッシュ**: 画像は`cached_network_image`によりディスクキャッシュされ、一度表示した画像は再ダウンロードしない。動画は`VideoPlayerController`をplaybackId単位でLRUキャッシュ（直近6件）し、画面外に出てもすぐには破棄せず、再スクロールで戻った際に再初期化なしで再生を継続する。
- **再生位置の記憶**: 一度再生された動画は最後の再生位置をplaybackId単位で記録し、キャッシュ上限超過等でコントローラーが一度破棄された後も、再度画面内に戻った際は最後の再生位置から再生を再開する（ゼロ秒に巻き戻らない）。

### 5.3 YouTube埋め込み・共有連携

YouTubeの動画は自前でホスティングせず、**公式の埋め込みプレーヤー経由でのみ**再生する（YouTube利用規約準拠）。

- 投稿本文からYouTube URLを検出（正規表現）し、`posts.external_video_provider='youtube'` / `external_video_id` に動画IDを抽出して保存。
- フィード表示時は `https://www.youtube.com/embed/{video_id}` を`webview_flutter`または`youtube_player_flutter`（内部的に公式IFrame Player APIを利用するラッパー）でインライン再生する。
- **YouTubeアプリの共有シートにRengaを表示させる**（プロダクト要件、詳細は [product.md — メディア共有](product.md#31-メディア共有画像動画投稿--youtube連携)）:
  - **Android**: `AndroidManifest.xml` に `<intent-filter>` で `ACTION_SEND` / `mimeType: text/plain` を宣言し、共有テキスト（YouTubeアプリが渡すのは動画タイトル+URLのテキスト）を受け取れるようにする。Flutter側は `receive_sharing_intent` パッケージで受信し、URLを正規表現抽出してCompose画面へ渡す。
  - **iOS**: 標準のURL Schemeだけでは共有シートに登場しないため、**Share Extension（ネイティブSwiftターゲット）をXcodeプロジェクトに追加**する必要がある。App Groupsでメイン アプリとデータを受け渡し、`receive_sharing_intent` パッケージが提供するiOS向けの実装パターンに従う。ネイティブ実装コストがあるため、優先度はAndroidより後（[product.md — ロードマップ Phase 2](product.md#8-mvpスコープ定義フェーズ分割)）とする。

### 5.4 セキュリティ・運用上の注意

- Mux API Token（Token ID / Secret）はSupabase Function Secretsで管理し、クライアントに一切露出させない（Direct Upload URLの発行は必ずEdge Function経由）。
- Mux Webhookはシグネチャ検証必須（`Mux-Signature` ヘッダー）。検証に失敗したリクエストは破棄する。
- アップロード可能な動画の長さ・サイズはEdge Function側でも上限を設け、悪意あるユーザーによる長時間動画の大量アップロードを防ぐ（コスト増大対策）。

## 6. Gemini AI活用アーキテクチャ

Rengaにおけるすべてのアプリケーション内AI機能は **Gemini API** に統一する。用途は2つ:
(A) サイレント・ドメイン・マッピング、(B) クイズ問題の自動生成と複数AIエージェントによる相互検証。
いずれもSupabase Edge Functions内から呼び出し、APIキーはFunction Secretsで管理する。

### 6.1 ドメインラベリング（サイレント・ドメイン・マッピング）

```
[投稿作成] → [Edge Function: label_post_domain]
   ├─ Gemini (軽量モデル, 例: gemini-flash 系) にテキストを送信
   ├─ プロンプトで固定タクソノミー（医療/自動車/歴史/…）からの分類 + 信頼度スコアを要求
   └─ posts.domain_labels に反映（信頼度が閾値未満の場合はラベル付与を見送る）
```

- 全投稿ではなく、一定文字数以上・シリアス投稿（TP消費投稿）を優先して実行し、API呼び出し回数を抑制する（12章）。
- 出力はJSON形式で厳密にスキーマ指定し、パース失敗時はラベル付与をスキップして処理を継続する。

### 6.2 クイズ自動生成 + マルチエージェント検証パイプライン

デイリーミッション・オンボーディング・ロック解除クイズで出題される問題は、最終的には人手で作らず
**Geminiによる「出題AI → 解答AI（複数） → 検証AI」の3段階パイプライン**で生成・自己検証してから
問題プール（`quiz_questions`）に投入する。目的は、生成AIが単独では起こしがちな「曖昧な問題」
「答えが一意に定まらない問題」「事実誤認を含む時事問題」を、後段の別AIロールでクロスチェックして除去すること。

**初期実装時（Claude Codeでの実装フェーズ）は、このパイプラインが稼働する前に手動で10問程度の
シードクイズを `quiz_questions` に `generated_by='human'`, `validation_status='approved'` として
直接投入し、オンボーディング/デイリーミッションが空にならないようにする。** 自動生成パイプラインは
このシードセットを土台に、Phase 3（[product.md — ロードマップ](product.md#8-mvpスコープ定義フェーズ分割)）で
段階的にフル稼働させる。

```
[Scheduled Edge Function: generate_quiz_batch] (夜間バッチ、問題種別×難易度ごとにプール残数を監視)
   │
   ├─ 1. Generator（出題AI）
   │     Gemini に question_type（logic / geometry / current_events）、difficulty、locale を指定して
   │     候補問題（設問文・選択肢・正解・解説）をJSON構造で生成させる。
   │
   ├─ 2. Solver（解答AI, 複数体）
   │     生成された設問と選択肢のみ（正解ラベルは渡さない）を、Generatorとは独立した
   │     複数回のGemini呼び出し（例: 温度を変えてN=3）に解かせる。
   │     複数ソルバーの回答が一致するか、Generatorの主張する正解と一致するかを集計し
   │     `solver_agreement_rate` として記録。
   │
   ├─ 3. Validator（検証AI）
   │     設問・選択肢・Generatorの正解・全Solverの回答ログをまとめて別のGemini呼び出しに渡し、
   │     以下の観点でレビューさせる:
   │       - 正解が一意に定まるか（選択肢の曖昧さ・複数正解の可能性）
   │       - 時事問題であれば事実として正確か（学習データの鮮度限界を踏まえ、断定的な最新事実は
   │         採用しない方針を指示に含める）
   │       - 差別的・攻撃的表現や特定属性への偏見がないか
   │       - 制限時間内（10〜20秒）で解答可能な難易度か
   │       - 既存プールとの類似度（同工異曲の出題になっていないか）
   │     Validatorは `approved | rejected | human_review` のいずれかを判定し、`validator_notes` に理由を残す。
   │
   └─ 4. 採否判定（Edge Function側のロジック、AIに丸投げしない）
         `solver_agreement_rate >= 閾値`（例 0.8）かつ `validator == approved` の場合のみ
         `quiz_questions` に `is_active = true` で投入。
         それ以外は `validation_status = 'rejected'` または `'human_review'` として保留し、
         プールには反映しない。
```

### 6.3 設計上のポイント

- **役割分離**: Generator/Solver/Validatorは同じGeminiモデルであっても、プロンプト（システム指示）を
  完全に分離し、Generatorの出力（特に「正解」ラベル）をSolverには一切見せない。
- **コストと精度のバランス**: Generator/Solverは軽量・高速なモデル（Flash系）を使い、Validatorのみ
  精度重視のモデル（Pro系）を使う構成を基本とする。無料枠のレート制限に収まるよう、バッチ処理は
  キューイングして間引く（12章）。
- **監査ログ**: どの生成バッチ（`quiz_generation_runs`）からどの問題が採用/却下されたかを全て記録する。
- **人間レビューのフック**: `human_review` 判定になったものは管理用ダッシュボード（将来実装）で
  運営が目視確認できるキューに入れる。
- **多言語生成**: `locale` を指定してGeminiに直接英語/日本語で生成させる（翻訳ではなくネイティブ生成）。デフォルトはenでの生成を優先し、jaは追加で生成するプールとして扱う。

### 6.4 AI生成コンテンツの品質・安全性ガードレール

- Gemini APIの安全性設定（有害コンテンツフィルタ）を有効化し、出力に対しても最終防波堤として
  キーワード/カテゴリベースの簡易フィルタをEdge Function側にも設置する。
- 生成問題・ドメインラベルの誤りが疑われる場合にユーザーが報告できる導線を将来的にFeed/Quiz画面に
  用意し、報告が集中した問題は自動的に `is_active = false` にする運用を検討する（Phase 3以降）。

### 6.5 テキスト翻訳

product.md 3.12.1節「投稿・DMメッセージの自動翻訳」に対応するEdge Function
`translate_text` を新設する。翻訳という用途にGeminiの汎用LLM呼び出しを使うのはコスト・レイテンシの
両面で非効率なため、翻訳専用の**Google Cloud Translation API v3 (Advanced)** を使う（他機能
（ドメインラベリング・クイズ生成・モデレーション）は引き続きGeminiのまま）。認証は8章
「通知アーキテクチャ」の`send_push_notification`が使うFirebase Admin SDKサービスアカウントJSONと
同じ鍵を流用し、`https://www.googleapis.com/auth/
cloud-platform`スコープの自己署名JWT→アクセストークン交換（同じ`send_push_notification`の実装）で
呼び出す。同じGCPプロジェクト（`chatapp-renga`）のサービスアカウントに「Cloud Translation API
User」（`roles/cloudtranslate.user`）ロールを追加付与する必要がある。ユーザー認証部分は
`label_post_domain`と同じパターン（AuthorizationヘッダーのユーザーJWT検証のみ、DB更新は行わない）に
倣う。

```
[投稿/DMメッセージ本文] → [Translate ボタンタップ] → [Edge Function: translate_text]
   ├─ 入力: { text: string, target_locale: 'en' | 'ja' }
   ├─ FIREBASE_SERVICE_ACCOUNT_JSON_B64（サービスアカウントJSONをbase64エンコードしたFunction
   │   Secret。生JSONを直接Secretに設定すると改行・引用符がCLI/シェル環境依存で壊れることがある
   │   ため、base64化して保持しFunction側でデコードする）でOAuth2アクセストークンを取得
   ├─ Google Cloud Translation API v3
   │   (https://translation.googleapis.com/v3/projects/{project_id}/locations/global:translateText)
   │   に { contents: [text], targetLanguageCode: target_locale, mimeType: 'text/plain' } をPOSTする
   └─ 応答: { translated_text: string } をクライアントへ返す（DBへの永続化は行わない）
```

- 翻訳結果はDBに保存せず、都度Google Cloud Translation API呼び出しの結果をクライアントに返すのみ
  （原文はいつでも`posts.body` / DMメッセージ本文からそのまま参照できるため、キャッシュはクライアント
  のメモリ内のみで十分。3.12.1節）。
- 失敗時（API呼び出し失敗・レート制限等）はエラーレスポンスを返し、クライアント側はスナックバー等で
  エラーを表示してボタン状態を元に戻す（ベストエフォートの`label_post_domain`とは異なり、翻訳は
  ユーザーの明示的な操作起点のため成功/失敗をそのままユーザーに伝える）。
- 事前準備: GCPプロジェクト`chatapp-renga`で「Cloud Translation API」を有効化し、Firebase Admin SDK
  サービスアカウント（`firebase-adminsdk-fbsvc@chatapp-renga.iam.gserviceaccount.com`）に
  「Cloud Translation API User」ロールを追加付与する。新規のAPIキー発行は不要（既存のサービス
  アカウント鍵をbase64化して`FIREBASE_SERVICE_ACCOUNT_JSON_B64`として流用する。.env.example参照）。

---

## 7. デマ撲滅フローと3ストライク実装

旧設計の「フェーズ制ロジックチェック（潜伏期/処刑期）」「上位5%ジャッジによる`logic_verdicts`投票」は
廃止し、product.md 3.4節の**真偽投票（`truth_judgment_requests` / `truth_votes`）1本**に統合した
（旧`battles`/`battle_bets`/`logic_verdicts`テーブルは新設計に伴い作成しない）。反論コメント機構
（旧Edit権限）も設けない（product.md 2.1節）。

### 7.1 真偽投票フロー（実装レベル）

```
[Discover投稿詳細画面]
   │
   ├─ 0. チケット取得（Edge Function: purchase_tickets / grant_daily_tickets）
   │      ├─ purchase_tickets: 一般ユーザーがTPでチケットを購入（1枚=100TP、まとめ買い割引はRemote
   │      │  Config `ticket_bulk_discount_tiers` で管理）。user_assets.tp_balanceを減算し
   │      │  ticket_countを加算、tp_transactions(reason='truth_vote_ticket_purchase')を記録
   │      └─ grant_daily_tickets: is_top_intellect_tier(auth.uid())のユーザーに対し、UTC日次で
   │         user_assets.last_daily_ticket_granted_at未更新なら+3枚を付与（pg_cronで日次実行、
   │         多重付与はlast_daily_ticket_granted_atのユニーク日付チェックで防止）
   │
   ├─ 1. リクエスト起票（Edge Function: request_truth_judgment）
   │      ├─ 呼び出し元が is_top_intellect_tier(auth.uid()) であることを検証
   │      │  （対象postのcontextはfeed/discoverいずれでも可。旧設計のdiscover限定は解禁済み）
   │      ├─ truth_judgment_requests に1行insert
   │      │  （author_intellect_percentile_snapshot=対象投稿者の現在のintellect_percentileをコピー、
   │      │   opens_at=now(), closes_at=now()+Remote Config `truth_judgment_window_hours`,
   │      │   quorum_threshold=Remote Config `truth_judgment_quorum` の値をコピー）
   │      └─ 元投稿者へFCM通知（4章）
   │
   ├─ 2. 投票（Edge Function: cast_truth_vote）
   │      ├─ is_top_intellect_tier(auth.uid())、request.status='voting'、closes_at未到達を検証
   │      ├─ profiles.intellect_percentile <= request.author_intellect_percentile_snapshot
   │      │  （投稿者本人と同格以上の知能階層のみ投票可、product.md 3.4節）を検証。ただし
   │      │  auth.uid() = request.requested_by（起票者本人）の場合はこの階層チェックを免除する
   │      ├─ user_assets.ticket_count > 0 を検証し、同一トランザクションでticket_countを-1
   │      │  （TP増減は発生しない。product.md 3.4.5節「チケット仲介方式」）
   │      ├─ voter_tier を投票時点のintellect_percentileから 'top5' | 'top25' に判定して記録
   │      │  （product.md 3.4.4節の2階建てメーター集計に使用）
   │      └─ truth_votes に1行insert（unique制約で1人1票を担保）。クライアント側は自分の投票が
   │         成立した直後にのみブラインド（モザイク）を解除して比率を表示する（product.md 3.4.2節）
   │
   └─ 3. 締切精算（Scheduled Function: resolve_truth_judgments、5〜10分毎のpg_cronでcloses_at超過分をポーリング）
          ├─ true_vote_count / false_vote_count（tier別内訳含む）を集計しrequestsへ書き込み
          ├─ 合計投票数 < quorum_threshold の場合:
          │    status='invalid'、resolved_verdict=null。全投票者へ消費チケットをticket_count+1で返還
          │    （TP側の記録は発生しない）
          └─ quorum達成の場合:
               resolved_verdict = (true_vote_count > false_vote_count)
               status='resolved'、posts.truth_verdict を更新
               的中側: 山分けボーナス = (総チケット数 × 100TP) ÷ 正解者数（product.md 3.4.3節の数理式）
                 を各正解者へ tp_transactions(reason='truth_vote_payout') としてプラットフォームが
                 新規発行（原資は敗者のチケットと紐付けない、完全に切り離す）
               外れ側: 追加処理なし（消費済みチケットは返還されず全損。TPの増減は発生しないため
                 tp_transactionsへの記録行も追加しない。監査は`truth_votes.payout_tp=0`で足りる）
               ドメインスコア加算: 的中投票者について、対象投稿のdomain_labelsごとに
                 user_domain_scores.correct_vote_streakを+1し、閾値超過でpromoted_to_domain_expert
                 をtrueにする（product.md 3.4.1節）
```

- **山分けボーナスの原資分離**: 敗者が失うのは投票権チケットのみ（TPではない）で、正解者への
  `truth_vote_payout`は常にプラットフォームが新規発行するTPとして記録する（product.md 3.4.3節
  「配当の原資分離」）。ユーザー間のTP移転が一度も発生しないため、ストア審査上「参加者間の
  賭博」ではなく「チケットを消費するゲームのクリア報酬」として説明できる。これによりTPの総量は
  投票イベントごとにわずかに増加（インフレ）しうるため、TPの総発行量は`tp_transactions`の
  集計で定期監視する（12章の運用監視に追加）。
- **リポスト時警告**: `reposts` insert前にクライアントが対象 `posts.truth_verdict` を確認。
  `false`（真偽投票で偽と確定済み）の場合、確認モーダルを表示してから続行させる。
  `truth_verdict`が`null`（未リクエスト/投票中/無効）の場合は警告を出さない。
- **バックアップ昇格**: `endorsements(kind='logic_endorse')` が閾値に達したら `posts.logic_verdict = 'endorsed'` にし、高知能限定タイムラインに優先表示されるようreach_scoreを加点（真偽投票とは独立した仕組み、product.md 3.6節）。

### 7.2 3ストライク・ペナルティ実装

- `truth_judgment_requests` が `resolved_verdict = false` で確定した際、Edge Function（`resolve_truth_judgment`の一部）が対象投稿の投稿者に対し `strikes` にレコードを追加する（`reason_request_id`に確定したリクエストのIDを記録）。
- ストライク発火閾値（累積「偽」確定回数）は Remote Config `strike_thresholds`（仮値 `[1, 3, 5]`）で管理し、該当回数に達するたびに1段階ずつ処理をEdge Function内で分岐実行:
  - 1st（累積1回）: `intellect_score` を大幅減点し `intellect_percentile` を再計算、`strike_expires_at = now() + 14 days` を設定してプロフィールに警告ラベルを表示。
  - 2nd（累積3回）: バッジ非表示になるよう `intellect_percentile` を強制的に閾値以下に設定するフラグ列を追加（`badge_suppressed_until`）、投稿権限ロック（`posting_locked_until`）。
  - 3rd（累積5回）: `is_permanently_banned` フラグを立てず、代わりに `profiles` の主要スコア列・`tp_balance`・フォロワー関連集計をリセットする「ソフトリセット」処理（アカウント自体は維持し、再出発とする）。
- 誤爆防止のため `appeals` テーブルで異議申し立てを受け付け（`target_type='truth_judgment'`で該当リクエストへの異議、または`target_type='strike'`でストライク自体への異議）、承認された場合はストライクを取り消し、罰則を巻き戻すロールバック処理を用意。

---

## 8. AIアシスト対策・不正検知

| 懸念 | 対策 |
|---|---|
| デイリーテストをAIに解かせる | 1問あたり制限時間を極小化（10〜15秒）。幾何学パズル・画像ベース問題・最新時事ロジック問題を混在させ、AIが単純テキストコピペで解きにくい形式にする。回答時間の統計的外れ値（人間離れした速さ・一定間隔）を検知しフラグを立てる |
| ロジックチェックの自動荒らし | 真偽審判リクエストの起票・投票は`Create`権限（上位25%以上）保持者に限定されるため無差別な荒らしの母数自体が絞られる。加えて最低ステーク額を高めに設定しリスクを持たせ、同一アカウントからの短時間大量リクエスト/投票をレートリミット |
| チャットでのAI壁打ち | 限定チャット（将来機能）は音声ディベート形式、または発言間隔を極めて短く制限する設計とする（MVPスコープ外） |

不正検知はEdge Functionでの後段バッチ処理（`quiz_responses` の応答時間分布分析）として実装し、疑わしいユーザーは自動ストライクではなく「要人力レビューキュー」に入れる（誤検知による無実ユーザーへの過剰罰則を避ける）。

なお、出題される問題自体の品質・妥当性はGeminiによる生成・検証パイプライン（6章）側で担保する。本章の対策は「人間のユーザーがAIを使って不正に解答する」ことへの防御であり、6章は「出題される問題自体が壊れていないこと」の保証という別レイヤーの話である点に注意。

---

## 9. Flutterアプリ構成（アーキテクチャ）

```
lib/
├── main.dart
├── app/
│   ├── router (go_router)
│   ├── theme (カスタムThemeData、フォント、カラートークン)
│   ├── l10n (ARBファイル: app_en.arb をテンプレートに app_ja.arb を追加、gen-l10nで生成)
│   └── di (Riverpod Providerの集約)
├── core/
│   ├── supabase_client.dart
│   ├── firebase/ (firebase_messaging初期化、トークン管理、remote_config初期化)
│   ├── network/ (Edge Function呼び出しラッパー)
│   └── utils/
├── features/
│   ├── onboarding/
│   ├── daily_mission/
│   ├── feed/
│   ├── compose/
│   ├── discover/ (真偽審判リクエスト・真偽投票UIを含む。独立battle機能は持たない、4章参照)
│   ├── profile/
│   └── notifications/
└── packages/
    └── renga_ui/ (デザインシステム: カスタムボタン、バッジ、カード、グラフ、アニメーション)
```

- **状態管理**: Riverpod。
- **ルーティング**: go_router（通知タップからのディープリンク解決もここで処理）。
- **通信**: `supabase_flutter` SDK + PostgREST/Realtime。Edge Function呼び出しは専用Repositoryでラップ。
- **認証**: `supabase_flutter` のメール/パスワード認証 + `google_sign_in` パッケージによるGoogle OAuth（Supabaseの `signInWithIdToken` でSupabase Authと連携）。
  - **Google新規登録時のプロフィール入力強制**: `signInWithIdToken`は未登録メールなら新規`auth.users`行を作成するが、この経路ではusername等の入力欄を経由しない。`handle_new_user`トリガーは`raw_app_meta_data->>'provider' = 'google'`かつ`raw_user_meta_data`にusernameが含まれない場合、`profiles.profile_completed = false`で行を作成する（メール/パスワード登録はusername未入力でもID由来のデフォルト値を許容する既存仕様のため対象外）。`lib/app/router.dart`のオンボーディングクイズ強制リダイレクトと同様のパターンで、`profile_completed = false`のユーザーは`/complete-profile`（サインアップ画面のusername入力フォームを`ProfileSetupForm`として切り出し再利用）以外へのアクセス時にそこへリダイレクトされ、保存完了後にホームへ進める。既存のGoogle経由未完了ユーザーもマイグレーションで同フラグをfalseに補正する。
- **プッシュ通知/設定配信**: `firebase_core` / `firebase_messaging` / `firebase_remote_config` / `firebase_crashlytics` / `firebase_analytics`。`firebase_messaging` はフォアグラウンド/バックグラウンド/終了状態の3パターンの受信ハンドラを実装し、トークン取得・更新時にSupabaseの `device_tokens` へ同期する。
- **広告**: `google_mobile_ads` を導入し、広告ユニットIDはRemote Config経由で配信。
- **メディア**: 画像選択・撮影は `image_picker`、動画選択・撮影は `image_picker`（video）を使用。動画はMuxへのDirect Upload（`http`パッケージによるPUTリクエスト）でアップロードし、再生は `video_player`（+ `chewie`）でHLSストリームを再生。YouTube埋め込みは `webview_flutter` または `youtube_player_flutter` を使用。共有シート受信（Android）は `receive_sharing_intent` を使用し、YouTubeアプリ等から共有されたURLをCompose画面にプリフィルする（詳細は [5章](#5-mux動画アーキテクチャ)）。
  - **スクロール連動の自動再生**: フィード内の動画は画面内可視割合を検知して自動再生/停止を切り替える（`visibility_detector`パッケージ等を利用。`ListView`の`itemBuilder`ごとに可視率を監視し、閾値超過時のみ`VideoPlayerController`を生成・再生してリソースを節約する）。フィード内はミュート・軽量プレビュー品質、全画面表示時のみフル品質HLSに切り替える（product.md 3.13節）。
  - **全画面メディアビューア**: 画像（複数枚、`PageView`+ドットインジケーター）・動画（下部シークバー＋つまみ）を共通の`FullscreenMediaViewer`ウィジェットで表示する。フィード側のサムネイル/軽量プレビューと全画面側のフル品質表示は同じ`playback_id`/`media_urls`を参照し、表示解像度のみ出し分ける。
- **多言語対応**: `flutter_localizations` + `gen-l10n`。既定ロケールは英語（`app_en.arb`）、日本語（`app_ja.arb`）を追加ロケールとして提供。端末ロケールが未対応言語の場合は英語にフォールバック。
- **デザインシステム分離**: `packages/renga_ui` をローカルパッケージ化し、Widgetbookでカタログ管理。
- **アニメーション**: `rive` または `lottie` をバッジ実績解除・真偽審判リクエスト確定時の結果発表に使用。
- **通報/モデレーション**: すべての投稿・動画・プロフィールに通報導線（`RengaReportSheet` 等の共通コンポーネント）を用意し、`reports` テーブルへ書き込む（詳細は [13章](#13-コンテンツモデレーショントrust--safety)）。
- **共有**: OS標準の共有シートを開くために `share_plus` を使用する（投稿の共有ボタン。3.12節）。`receive_sharing_intent`（既存導入済み、5.3節）は他アプリからの共有受信専用であり、送信側の共有には使わない。
- **設定・編集系UIの方針**: Profile画面の「編集」ボタンのように、既存の読み取り専用ビュー上で完結する軽い編集は引き続き`showModalBottomSheet`のボトムシートに分離する（`lib/features/feed/intellect_badge.dart`の説明ボトムシートと同じ角丸・パディングの意匠を踏襲）。投稿の新規作成（Compose）も同じ方針で、Feed画面のAppBar投稿ボタンから`ComposeSheet`（`lib/features/feed/compose_sheet.dart`）を`showModalBottomSheet`（`isScrollControlled: true`）で開く（`lib/features/profile/profile_edit_sheet.dart`の`ProfileEditSheet`と同一パターン）。YouTubeアプリ等からの共有シート起動（5.3節）時は、`go_router`の`/compose`ルートを共有テキスト付きディープリンクの薄い受け口として残し、遷移後すぐに同じ`ComposeSheet`をボトムシートとして開く。一方、**Settings画面配下の各設定変更**（プロフィール編集・パスワード変更・アカウント削除・表示設定・表示言語）は、Settings画面自体をリンク一覧に留め、それぞれ`go_router`の子ルート（例: `/settings/profile`, `/settings/password`, `/settings/delete-account`, `/settings/display`, `/settings/language`）としてフルページ遷移させる方針に統一する（product.md 3.11節）。**ボトムシート共通ルール**: どちらの形式でも「キャンセル」専用ボタンは置かず、シートを閉じる操作自体をキャンセルとして扱う（product.md 5章）。
- **アカウント削除**: クライアントから`auth.users`を直接削除できないため、Supabase Edge Function `delete_account`（サービスロールキーを保持）を新設し、認証済みユーザー自身のリクエストのみ受け付けて`auth.users`を削除する（`profiles`は`on delete cascade`で連動削除）。呼び出し前にクライアント側で確認ステップ（再ログインまたはユーザー名再入力）を必須とする。
- **他ユーザーのプロフィール閲覧**: `go_router`に`/profile/:userId`ルートを追加し、フィード・コメント等のアバター/ユーザー名タップから遷移する。既存の`/profile`（自分のプロフィール、ボトムナビタブ）とはルート・Widgetを分け、`ProfilePage`は`userId`を受け取れるよう拡張し、閲覧者が本人かどうかで編集ボタン・ログアウトボタン等の表示を出し分ける（product.md 3.10節）。

---

## 10. マネタイズ（AdMob）実装

- Flutterパッケージは `google_mobile_ads` を使用。
- 広告ユニットIDはハードコードせず、Firebase Remote Configから配信し、A/Bテストや緊急停止（`ads_enabled` フラグ）を可能にする。
- テスト時はAdMobのテスト広告ユニットIDを使用し、本番IDとの切り替えをビルドフレーバー（dev/prod）で管理する。

### セットアップ手順（CLI/コンソール併用）

AdMobの広告ユニット作成自体はAdMob管理画面での操作が必要（CLI非対応）だが、アプリ側の紐付けは以下で行う。

1. AdMobコンソールでアプリ登録（Android/iOS、パッケージ名 `com.minnya.renga`）、広告ユニット（ネイティブ/バナー/インタースティシャル）を作成
2. AndroidManifest.xml / Info.plistにAdMobアプリID（`ca-app-pub-...~...`）を設定
3. `flutter pub add google_mobile_ads` — パッケージ追加
4. Remote Configテンプレート（`remoteconfig.template.json`）に広告ユニットIDと `ads_enabled` フラグを追加し、`npx firebase-tools deploy --only remoteconfig` で配信
5. AdMobはFirebaseプロジェクトとリンク可能なため、Firebaseコンソール上でAdMob連携を有効化し、Analyticsと広告パフォーマンスの相関を計測できるようにする

---

## 11. 開発環境・CLI運用

### 11.1 Flutterプロジェクト初期化

```
flutter create --org com.minnya --project-name renga .
```

`--org com.minnya` を指定することで、Android/iOSのパッケージ識別子が自動的に `com.minnya.renga` になる。

### 11.2 Supabase CLI

Supabase CLIはグローバルインストールせず `npx supabase <command>` で都度実行する前提。CLI操作に必要な環境変数は [.env.example](../.env.example) に定義する（`SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD` 等）。

1. `npx supabase init` — プロジェクト初期化（`supabase/` ディレクトリ生成）
2. `npx supabase login` — Supabaseアカウント連携（`SUPABASE_ACCESS_TOKEN` があれば非対話でも可）
3. Supabaseダッシュボードでプロジェクトを新規作成する際、**Region: US（East/Westいずれか）**を選択（CLIの `init`/`link` 自体にリージョン指定はなく、プロジェクト作成時にダッシュボードまたは `supabase projects create --region <region>` で指定）
4. `npx supabase link --project-ref $SUPABASE_PROJECT_REF` — クラウド無料プロジェクト（プロジェクト名 `renga`）と連携
5. `npx supabase migration new <name>` — マイグレーションファイル作成（1章のSQLをここに配置）
6. `npx supabase db push` — クラウドDBへマイグレーション反映
7. `npx supabase functions new <name>` — Edge Function雛形作成（FCM送信用・Gemini呼び出し用Functionもここに含む）
8. Google Sign-Inの有効化: Supabaseダッシュボード > Authentication > Providers > Google を有効化し、Google Cloud ConsoleでOAuthクライアントID/シークレットを発行して登録（`GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` を `.env` に保持）
9. シークレット登録:
   - `npx supabase secrets set GEMINI_API_KEY=$GEMINI_API_KEY` — Gemini API（ドメインラベリング・クイズ生成パイプライン用、13章のモデレーションでも使用）
   - `npx supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(cat firebase-service-account.json)"` — Firebase Admin SDK用サービスアカウント鍵
10. `npx supabase functions deploy <name>` — クラウドへデプロイ
11. `npx supabase gen types dart --linked` — Flutter用の型生成

ローカル開発時はDockerベースの `npx supabase start` によるローカルスタックも選択可能。

### 11.3 Firebase CLI / FlutterFire CLI

Firebase側もグローバル常駐インストールを避け、`npx firebase-tools` および `flutterfire_cli` をプロジェクトスクリプト化して運用する。必要な環境変数（`FIREBASE_PROJECT_ID`, `FIREBASE_TOKEN`, `GOOGLE_APPLICATION_CREDENTIALS` 等）は [.env.example](../.env.example) を参照。

1. `npx firebase-tools login` — Firebaseアカウント連携（CI環境では `firebase login:ci` で発行した `FIREBASE_TOKEN` を使い非対話ログイン）
2. `npx firebase-tools projects:create $FIREBASE_PROJECT_ID` — Firebaseプロジェクト作成（既定は `renga`。同名が使用済みの場合は代替IDを `.env` で上書き）
3. `dart pub global activate flutterfire_cli` → `flutterfire configure --project=$FIREBASE_PROJECT_ID` — iOS/Android両プラットフォームの設定ファイル（`google-services.json` / `GoogleService-Info.plist`）と `firebase_options.dart` を自動生成。Bundle ID/applicationIdは `com.minnya.renga` を指定。
4. Remote Configテンプレートを `remoteconfig.template.json` としてリポジトリ管理し、`npx firebase-tools deploy --only remoteconfig` でデプロイ
5. Crashlytics/Analyticsは基本Flutterプラグイン側のビルド設定で完結するため、CI/CDパイプラインに組み込む
6. FCMのサーバーキーではなく、**サービスアカウントJSON（HTTP v1 API用）**を発行し、`GOOGLE_APPLICATION_CREDENTIALS` に指定したパスに配置。Supabase Edge Functionのシークレットとしても登録する（`gcloud iam service-accounts keys create` で発行）

### 11.4 Gemini API セットアップ

1. Google AI Studio（`aistudio.google.com`）でAPIキーを発行（無料枠あり）し、`.env` の `GEMINI_API_KEY` に設定
2. `npx supabase secrets set GEMINI_API_KEY=$GEMINI_API_KEY` でEdge Function用に登録（クライアントには一切渡さない）
3. Edge Function内からHTTPS経由でGemini APIを直接呼び出す
4. ドメインラベリング用・クイズ生成用（Generator/Solver/Validator）でプロンプトを分離し、それぞれ専用のEdge Function（例: `label_post_domain`, `generate_quiz_batch`）として実装する（6章）

### 11.5 Mux セットアップ

Muxには専用CLIはなく、ダッシュボード操作とAPIキー発行が中心となる。

1. Mux Dashboard（`dashboard.mux.com`）でアカウント作成し、Access Token（Token ID / Token Secret）を発行
2. `.env` に `MUX_TOKEN_ID` / `MUX_TOKEN_SECRET` を設定
3. `npx supabase secrets set MUX_TOKEN_ID=$MUX_TOKEN_ID MUX_TOKEN_SECRET=$MUX_TOKEN_SECRET` — Edge Function（Direct Upload発行用）に登録
4. Edge Function `mux_webhook` をデプロイし、そのURL（例: `https://<project-ref>.functions.supabase.co/mux_webhook`）をMux Dashboardの Webhooks 設定に登録
5. Webhook Signing Secretを発行し、`.env` の `MUX_WEBHOOK_SIGNING_SECRET` に設定 → `npx supabase secrets set MUX_WEBHOOK_SIGNING_SECRET=...` で登録（署名検証に使用、5章参照）

### 11.6 GitHub Pages セットアップ（利用規約・プライバシーポリシー・ランディングページ公開）

利用規約・プライバシーポリシーに加え、アプリ紹介用のランディングページ（Play Store/App Storeへの
リンク誘導、product.md — [7章 Playストアリリース準備 — ランディングページ](product.md#ランディングページgithub-pages)参照）も
まとめてリポジトリの `docs/` フォルダで管理し、GitHub Pagesで静的サイトとして公開する
（`design/` フォルダの内部設計ドキュメントとは別に、`docs/` は公開用に予約する）。

1. リポジトリ設定 `Settings > Pages` を開く
2. **Source** を `Deploy from a branch` に設定
3. **Branch** を `main`、フォルダを `/docs` に設定して保存
4. 数分後、`https://minnya.github.io/chatapp-renga/` で公開される
   - ランディングページ: `https://minnya.github.io/chatapp-renga/`（`docs/index.html`）
   - 利用規約: `https://minnya.github.io/chatapp-renga/terms.html`
   - プライバシーポリシー: `https://minnya.github.io/chatapp-renga/privacy.html`
5. `docs/terms.md` / `docs/privacy.md` 内の `support@renga-app.com` を実際に監視するサポートメールアドレスに置き換える（公開前に必須）
6. `docs/index.html` のGoogle Play / App Storeバッジのリンク先を、実際のストア掲載URL確定後に差し替える（Phase 1時点ではApp Store側は「Coming soon」の非活性リンクで暫定運用）
7. これらのURLをGoogle Play Consoleのストア掲載情報（プライバシーポリシーURL・マーケティングURL）・アプリ内設定画面にそれぞれ設定する

この構成により、Flutter/Firebase/Supabase/Gemini/Mux側それぞれの設定変更をCLIコマンドとして再現可能にし、チーム内・CI環境での再セットアップを容易にする。

### 11.7 CI/CDパイプライン（GitHub Actions）

`production` ブランチへのマージからGoogle Play Store（`production`トラック）への配信までを、GitHub Actionsの2つのワークフローで自動化する。GitHub Releaseの下書き（Draft）を人間が確認・編集してから公開（Published）する工程を挟むことで、リリースノートの品質確認とリリースタイミングの制御を両立する。

**重要な制約**: `deploy_to_play_store.yml`は必ず**人がGitHub UI上で手動で「Publish release」を実行する**ことで起動する。デフォルトの`GITHUB_TOKEN`を使ってAPI経由（`gh release create`等）でreleaseを作成・公開しても、GitHub Actionsの無限ループ防止仕様により、その`release: published`イベントは他のワークフローの新規トリガーにならない。そのため`create_gh_release_draft.yml`は必ず`--draft`付きでReleaseを作成し、公開操作は人手に委ねる設計とする（PATを使えばAPI経由でも連鎖起動できるが、権限管理の複雑さを避けるため現状は採用しない）。

```
[production へのマージ] → create_gh_release_draft.yml
   └─ GitHubの generate_release_notes 機能でマージ済みPR群からリリースノートを自動生成し、
      GitHub Release の下書き（Draft）を作成する

[人間が下書きを確認・編集し、Release を Publish] → deploy_to_play_store.yml
   ├─ 1. gh release view で公開時点の確定リリースノートを取得し、Playストアの文字数制限（500文字）
   │     に収まるよう整形して android/whatsnew/whatsnew-ja-JP に書き出す
   ├─ 2. GitHub Secrets の ANDROID_KEYSTORE_BASE64 をデコードし、CIワークスペース内に
   │     upload-keystore.jks を一時復元する（ジョブ終了後は使い捨て、リポジトリには残さない）
   ├─ 3. ANDROID_KEYSTORE_PATH / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS /
   │     ANDROID_KEY_PASSWORD を環境変数として注入し、flutter build appbundle --release を実行
   ├─ 4. 生成した .aab を対象の GitHub Release に成果物として添付
   └─ 5. r0adkll/upload-google-play アクションで .aab とリリースノートを
         Google Play の production トラックへアップロード
```

**署名鍵の管理方針**:

- 本番アップロードキー（`upload-keystore.jks`）はリポジトリにコミットしない。ローカルで `keytool -genkeypair` により生成し、開発者のマシン等、リポジトリ外の安全な場所に保管する。
- CIでの利用のため、鍵をBase64エンコードして以下のGitHub Secrets（`Settings > Secrets and variables > Actions`）に登録する。

| Secret名 | 内容 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `upload-keystore.jks` をBase64エンコードした文字列（CI上でデコードして復元） |
| `ANDROID_KEYSTORE_PASSWORD` | ストアパスワード |
| `ANDROID_KEY_ALIAS` | 鍵のエイリアス名 |
| `ANDROID_KEY_PASSWORD` | キーパスワード |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | `r0adkll/upload-google-play` 用のGoogle Playサービスアカウント鍵（JSON） |

- `android/app/build.gradle.kts` の `signingConfigs.release` は、CI環境から上記4つの環境変数（`ANDROID_KEYSTORE_PATH` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`）が揃っている場合はそれを優先し、揃っていない場合はローカルの `android/key.properties`（Git管理外、開発者手元のみ）を読み込むフォールバック構成とする。どちらも存在しない場合は従来通りdebug鍵で署名し、`flutter run --release` のローカル動作を妨げない。

---

## 12. 無料枠を前提とした制約とスケーリング方針

Supabase無料プランの主な制約（DB 500MB、月間Edge Function実行数・帯域制限、7日でのプロジェクト一時停止（非アクティブ時）等）を踏まえ、以下を設計方針とする。

- **重い集計はバッチ化**: パーセンタイル再計算・真偽審判リクエストの締切精算は都度リアルタイム計算せず、Scheduled Functionで数分〜数時間おきに実行しキャッシュ列に反映。
- **メディアは圧縮・サイズ制限**: Storage容量節約のため、アップロード時にクライアント側でリサイズ・圧縮してから送信。
- **Gemini API呼び出しの間引き**: ドメインラベリングは全投稿ではなく一定文字数以上・シリアス投稿優先で実行。クイズ自動生成バッチも問題プールの残数が閾値を下回った場合のみ実行し、Gemini APIの無料枠のレート制限内に収まるようEdge Function側でキューイング・レートリミットを行う。
- **TP発行量の監視**: 真偽投票の的中配当（`truth_vote_payout`）はプラットフォームが新規発行するTPのため、`tp_transactions`の集計で発行/没収の収支を定期監視し、インフレが過度に進む場合は配当倍率・クォーラム閾値をRemote Config側で調整する（7章）。
- **将来のスケール**: ユーザー数増加時はSupabase Proプランへの移行、または集計処理を専用ワーカーへ切り出す拡張ポイントを設計上残す。

Firebase側はSpark（無料）プランを前提とする。

- **Remote Configのフェッチ頻度制限**: アプリ起動毎の高頻度フェッチは避け、キャッシュ有効期限（例: 1〜12時間）を設定する。
- **Crashlytics/Analyticsはそのままでも無料枠内で十分**。
- **FCM送信はSupabase Edge Function経由に一本化**: Firebase Functions（Blazeプラン必須）は使わず、Supabase Edge Functions + Firebase Admin SDKでの送信に統一することで、Firebase側を完全にSparkプラン内に収める。

Mux（動画基盤）は開発初期を **Free プラン**（月間配信100,000分無料、保存本数は最大10本まで、オンデマンドのみ）で開始し、規模拡大時に **Pay as you go**（保存本数無制限、$20分の月次クレジット付き）または **Pre-pay**（$20/月で$100分クレジット、$500/月で$1,000分クレジット等）へ切り替える前提とする（詳細は[5章](#5-mux動画アーキテクチャ)）。プラン切り替えはMux Dashboardの請求設定変更のみで、アプリ側の実装変更は不要。

- **保存本数10本の上限監視（Freeプラン運用時）**: `videos` テーブルの `status='ready'` 件数を定期チェックし、上限に近づいたら運用者に通知するEdge Function/Scheduled Functionを用意する。開発・検証段階では不要動画の削除で凌ぎ、本番リリース前にPay as you goへ切り替える。
- **アップロード動画の長さを制限**: 1動画あたりの最大長（例: 60〜90秒）をEdge Function側で強制し、配信分数（コスト）を予測可能にする。
- **配信解像度の上限設定**: Mux側のエンコード設定で過剰に高いビットレート/解像度を避け、月間配信100,000分の枠内に収まりやすくする。
- **本番移行の目安**: Play Storeへの一般公開時点では保存本数10本の制約が現実的でなくなるため、Pay as you goへの切り替えを前提にスケジュールしておく。

---

## 13. コンテンツモデレーション・Trust & Safety

[7章](#7-デマ撲滅フローと3ストライク実装)の「ロジック破綻認定」はあくまで**言説の質（デマ・論理破綻）**を扱うレイヤーであり、
暴力的・性的・誹謗中傷的コンテンツ等の**安全性（Trust & Safety）**は別レイヤーとして扱う。画像・動画投稿を
サポートする以上、Google Playの「ユーザー生成コンテンツ（UGC）ポリシー」が要求する
「通報・ブロック・迅速な対応フロー」を実装することは必須要件とする。

### 13.1 方針: 自動チェック + 通報ボタン

- **自動一次チェック**: 投稿（画像・動画サムネイル・テキスト）をGeminiのマルチモーダル機能でスクリーニングし、
  暴力・性的コンテンツ・ヘイトスピーチ・自傷/自殺関連・CSAM等のカテゴリに抵触する疑いがあれば
  `moderation_checks.verdict = 'flagged'` とし、当該投稿を**公開前または公開直後に非表示**にする
  （`posts.reach_score = 0` 相当のシャドー処理、削除ではなく人間レビュー待ちの保留状態にする）。
- **通報ボタン**: すべての投稿・動画・プロフィールに通報導線を設置。`reports` にレコードを作成し、
  一定数の通報が集中したコンテンツは自動的に一時非表示にして人間レビューキューに送る。
- **CSAM（児童性的搾取コンテンツ）関連は自動フラグ即座に非表示+法的対応フローへ**。曖昧判定は許容せず、
  疑わしきは非表示を優先する（false positiveのコストよりfalse negativeのコストが著しく大きい領域のため）。

### 13.2 処理フロー

```
[投稿作成: 画像/動画/テキスト]
   │
   ├─ 1. Edge Function `moderate_content` がGemini (multimodal) に
   │      テキスト本文 + 画像 / 動画サムネイル+抽出フレームを送信
   │
   ├─ 2. Gemini判定結果を `moderation_checks` に記録
   │      ├─ approved      → 通常通り公開
   │      ├─ flagged       → 公開停止（reach_score=0）+ 人間レビューキューへ
   │      └─ human_review  → 公開はするが人間レビューキューにも追加（グレーゾーン）
   │
   └─ 3. 動画の場合はMux Webhook（5章）でサムネイル確定後に実行
         （アップロード直後の一次チェックはクライアント側のサムネイル/先頭フレームで簡易実施）
```

- ユーザー通報（`reports`）も同じ人間レビューキューに合流させ、運営が一元管理する。
- **24時間以内の一次対応**（非表示判断 or 却下判断）を運用SLAとして設定し、レビューキューの経過時間を
  可視化する管理画面（最小構成でよいが、Supabase StudioのSQLビューだけに頼らず、簡易な社内管理UIを
  Phase 1のうちに用意することを推奨）。
- 誤検知・誤通報対策として、対象ユーザーへの通知と異議申し立て（`appeals`、[7章](#7-デマ撲滅フローと3ストライク実装)の仕組みを流用）を用意する。

### 13.3 利用規約・年齢レーティングとの関係

- コンテンツレーティングはMature 17+ / 18+相当を想定（論破・対立煽り要素があるため）。ストアの
  IARCアンケートでは「ユーザー生成コンテンツあり」「対立・議論を煽る要素あり」に正直に回答する。
- 利用規約（Terms of Service）・プライバシーポリシーに、通報・モデレーション・アカウント停止の
  ルールを明記し、[18章 Playストアリリース準備](product.md#7-playストアリリース準備)のストア掲載情報と整合させる。
- 未成年ユーザーの扱い（年齢確認の仕組みは自己申告ベースが現実的）、悪意ある大量通報（荒らしによる
  通報スパム）への対策（同一ユーザーからの通報頻度レートリミット等）もPhase 1で最低限考慮する。

---

## 14. 運用体制・コスト概算

自動化パイプライン（Gemini検証、AI自動モデレーション、3ストライク自動判定等）は「外れ値・グレーゾーン」を
残す設計であり、**継続的な人手対応が前提**であることを明記する。実装完了後の運用フェーズで必要になる作業を
以下に整理する。

### 14.1 人手対応が必要な運用タスク

| 領域 | 内容 | 頻度目安 |
|---|---|---|
| Trust & Safety | `reports` / `moderation_checks` の `human_review` キューのレビュー（24時間SLA）、CSAM等重大案件の当局対応判断（[13章](#13-コンテンツモデレーショントrust--safety)） | 常時（件数依存） |
| ストライク/異議申し立て | `appeals` のレビューと巻き戻し判断（[7章](#7-デマ撲滅フローと3ストライク実装)） | 発生都度 |
| クイズ品質 | Gemini生成問題の `human_review` 判定分のレビュー、時事問題の陳腐化対応、専門領域タクソノミーの追加・改訂（[6章](#6-gemini-ai活用アーキテクチャ)） | 週次〜月次 |
| Mux（動画） | Freeプラン保存10本の監視・Pay as you go切替（ダッシュボード操作、API不可、[5章](#5-mux動画アーキテクチャ)） | 成長に応じて都度 |
| AdMob | 広告ユニット作成（コンソール操作、CLI不可）、ポリシー違反監視、支払い口座設定（[10章](#10-マネタイズadmob実装)） | 初期設定＋随時 |
| Supabase/Firebaseインフラ | DB容量・Edge Function実行数の閾値監視とProプラン移行判断、7日非アクティブでのプロジェクト一時停止回避、シークレットのローテーション（[12章](#12-無料枠を前提とした制約とスケーリング方針)） | 月次＋随時 |
| Gemini API | 無料枠のレート制限・コスト監視、有料課金への切替判断、プロンプトのチューニング | 週次〜月次 |
| Google Play Console | 審査提出・ポリシー指摘対応、データセーフティフォーム維持、コンテンツレーティング更新、段階的ロールアウト監視 | リリース都度 |
| 利用規約/プライバシー | データ削除・開示請求対応（自動化未設計、問い合わせベース）、規約更新（[docs/terms.md](../docs/terms.md) / [docs/privacy.md](../docs/privacy.md)） | 発生都度 |
| カスタマーサポート | サポートメール問い合わせ対応 | 常時 |
| セキュリティ | スコア操作・TP消費悪用等、自動検知対象外の経済的搾取パターンの目視監視 | 随時 |

自動化パイプラインの外れ値を拾う一次窓口が最低1名、継続的に必要になる運用設計である点に留意する。

### 14.2 外部リソースの予想コスト（MVP規模、米ドル/月・概算）

料金体系（特にAI/クラウド系）は変動しやすいため、実装・運用開始時に各サービスの最新料金ページで
再確認すること。

| サービス | 無料枠での費用 | 成長後の目安 | 備考 |
|---|---|---|---|
| Supabase | $0（DB 500MB等の範囲内） | Pro: $25/月〜 | 容量/実行数超過で移行 |
| Firebase | $0（Sparkプランのみで完結する設計） | 基本的にBlaze不要 | FCM/Remote Config/Crashlytics/Analyticsは無料枠で十分 |
| Gemini API | $0〜数ドル/月（Flash系は安価） | 数十ドル/月〜（投稿数・クイズ生成量に比例） | 料金は変動しやすく実装時に要再確認 |
| Mux | $0（配信10万分/月、保存10本まで） | $20〜100+/月（Pay as you go、$20分クレジット込み） | 動画数・視聴数に比例 |
| Google AdMob | $0（広告掲載は無料、収益源） | — | Googleが広告収益の一部を手数料として差し引く |
| Google Play Developer | 取得済み（$25買い切り） | — | 追加費用なし |
| GitHub Pages | $0（publicリポジトリの場合） | privateリポジトリの場合GitHub Pro等が必要な場合あり | リポジトリの公開設定を要確認 |
| 独自ドメイン（任意） | $0（`github.io` 使用時） | $10〜15/年 | 現状は `github.io` のままで問題なし |

開発初期〜小規模運用は実質ほぼ無料枠内に収まる設計だが、ユーザー数・動画投稿量の増加でSupabase Pro +
Mux Pay as you goへ移行すると、目安として**月額$50〜150程度**のレンジに乗る想定。

---

## 15. ダイレクトメッセージ

[product.md 3.17節「ダイレクトメッセージ（DM）」](product.md#317-ダイレクトメッセージdm)に対応する実装詳細。

### 15.1 データモデル

```sql
-- 1対1会話。(user_a_id, user_b_id) はユーザーIDの昇順で正規化して保持し、
-- 同じ2人の会話が重複作成されないようにunique制約で担保する。
create table public.dm_conversations (
  id uuid primary key default gen_random_uuid(),
  user_a_id uuid not null references public.profiles(id), -- 常にuser_b_idより小さいUUID
  user_b_id uuid not null references public.profiles(id),
  last_message_at timestamptz not null default now(), -- 一覧のソート・プレビュー更新に使う非正規化列
  created_at timestamptz not null default now(),
  unique (user_a_id, user_b_id),
  check (user_a_id < user_b_id)
);

-- メッセージ本体。
create table public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.dm_conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id),
  body text, -- テキストメッセージ（画像/動画のみの送信時はnull可）
  media_type text not null default 'text', -- text | image | video
  media_url text, -- 画像URL（Supabase Storage）。動画はmux_playback_idで管理
  mux_playback_id text, -- 動画メッセージの場合のMux再生ID（5章のMuxアーキテクチャを流用）
  read_at timestamptz, -- 受信者が既読にした時刻。nullは未読
  created_at timestamptz not null default now()
);

-- 会話単位のブロック（片方向）。ブロックした側からのみ有効。
create table public.dm_blocks (
  blocker_id uuid not null references public.profiles(id),
  blocked_id uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

-- 会話の自分側のみの論理削除（3.17節「削除は自分の一覧からのみ非表示」）。
create table public.dm_conversation_deletions (
  conversation_id uuid not null references public.dm_conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  deleted_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
```

- `dm_conversations`は`user_a_id < user_b_id`のcheck制約で正規化し、どちらから始めても同じ会話に
  解決されるようにする（アプリ側でinsert時に`least()`/`greatest()`相当の並び替えを行う）。
- 削除後に相手から新規メッセージが届いた場合は、`dm_conversation_deletions`の該当行を削除して
  一覧に復帰させる（＝相手が退会しない限り会話自体は消えない、Instagram/X等と同様の挙動）。

### 15.2 RLS方針

- `dm_conversations` / `dm_messages`: selectは`user_a_id`/`user_b_id`（メッセージは会話の参加者）が
  `auth.uid()`と一致する場合のみ許可。insertは自分がその会話の参加者、かつ相手を自分がブロックしておらず
  相手からもブロックされていない場合のみ許可（`dm_blocks`を参照するinsertポリシー）。
- `dm_blocks`: 自分が`blocker_id`の行のみselect/insert/delete可能。
- `dm_conversation_deletions`: 自分が`user_id`の行のみselect/insert/delete可能。

### 15.3 Realtime・通知

- Flutterクライアントは会話画面を開いている間、Supabase Realtime（Postgres Changes）で
  `dm_messages`の`conversation_id = 該当会話`をフィルタしたINSERTイベントを購読し、ポーリングなしで
  新着メッセージを即座に表示する。
- DM一覧画面では、ログインユーザーが参加する全会話の`dm_messages` INSERTイベントを購読し、
  該当会話のプレビュー・未読バッジ・並び順（`last_message_at`）をリアルタイム更新する。
- プッシュ通知: メッセージinsert時のDB trigger（またはEdge Function経由）で、受信者が該当会話画面を
  開いていない場合にFCM通知を送る（4章のFirebase連携を流用）。「開いているかどうか」の判定は
  Phase 1では簡易的に「アプリがフォアグラウンドで該当会話画面を表示中か」をクライアント側で
  Supabase Presenceに反映し、送信側/Edge Function側で参照する方式を想定（実装コストが高い場合は
  Phase 1では「常に通知を送るが、当該会話を開いている端末側で通知を抑制する」という簡易版でも可）。

### 15.4 添付メディア

- 画像: 3.1節の投稿画像と同様、`post-images`バケットとは別に`dm-media`バケットへ`{userId}/{fileName}`で
  アップロードし、公開URLを`dm_messages.media_url`へ保存する。
- 動画: 5章のMux Direct Uploadフローを流用し、アップロード完了後の`mux_playback_id`を
  `dm_messages.mux_playback_id`へ保存する。DM内動画はフィード同様HLS再生する。
