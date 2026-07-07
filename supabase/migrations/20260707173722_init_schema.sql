-- design/system.md 1章のデータモデルを実体化する初期マイグレーション。
-- 全テーブルでRLSを有効化する前提（同章の補足）に基づき、テーブルごとに
-- enable row level security と最低限の公開読み取り/本人書き込みポリシーを付与する。

create extension if not exists pgcrypto;

-- ユーザープロフィール（auth.usersと1:1）
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text,
  avatar_url text,
  bio text,
  locale text not null default 'en',
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
  media_type text not null default 'text',
  media_urls text[],
  external_video_url text,
  external_video_provider text,
  external_video_id text,
  post_type text not null default 'normal',
  staked_tp numeric not null default 0,
  domain_labels text[] not null default '{}',
  logic_verdict text not null default 'unverified',
  broken_logic_score numeric not null default 0,
  reach_score numeric not null default 0,
  created_at timestamptz not null default now()
);

-- 動画（Mux連携）
create table public.videos (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  uploader_id uuid not null references public.profiles(id),
  mux_upload_id text,
  mux_asset_id text,
  mux_playback_id text,
  status text not null default 'pending',
  duration_seconds numeric,
  thumbnail_url text,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- リポスト
create table public.reposts (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id),
  user_id uuid not null references public.profiles(id),
  acknowledged_warning boolean not null default false,
  created_at timestamptz not null default now(),
  unique(post_id, user_id)
);

-- Endorse（お墨付き）
create table public.endorsements (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id),
  endorser_id uuid not null references public.profiles(id),
  domain text,
  kind text not null,
  created_at timestamptz not null default now(),
  unique(post_id, endorser_id, kind)
);

-- ロジックチェック・バトル
create table public.battles (
  id uuid primary key default gen_random_uuid(),
  target_post_id uuid not null references public.posts(id),
  challenger_id uuid not null references public.profiles(id),
  challenger_post_id uuid references public.posts(id),
  status text not null default 'active',
  challenger_stake_tp numeric not null default 0,
  defender_stake_tp numeric not null default 0,
  winner text,
  resolves_at timestamptz not null,
  created_at timestamptz not null default now()
);

-- 観客ベット
create table public.battle_bets (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.battles(id),
  user_id uuid not null references public.profiles(id),
  side text not null,
  amount_tp numeric not null,
  payout_tp numeric,
  created_at timestamptz not null default now(),
  unique(battle_id, user_id)
);

-- ドメイン別専門スコア
create table public.domain_scores (
  user_id uuid not null references public.profiles(id),
  domain text not null,
  score numeric not null default 0,
  badge_tier text,
  updated_at timestamptz not null default now(),
  primary key (user_id, domain)
);

-- クイズ自動生成バッチの実行ログ（quiz_questionsから参照されるため先に作成）
create table public.quiz_generation_runs (
  id uuid primary key default gen_random_uuid(),
  question_type text not null,
  locale text not null default 'en',
  target_difficulty int not null,
  generator_model text not null,
  solver_models text[] not null,
  validator_model text not null,
  candidates_generated int not null default 0,
  candidates_approved int not null default 0,
  status text not null default 'running',
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

-- IQテスト問題プール
create table public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  question_type text not null,
  locale text not null default 'en',
  payload jsonb not null,
  correct_answer text not null,
  difficulty int not null default 1,
  time_limit_seconds int not null default 15,
  is_active boolean not null default true,
  generated_by text not null default 'gemini',
  generation_run_id uuid references public.quiz_generation_runs(id),
  validation_status text not null default 'pending',
  solver_agreement_rate numeric,
  validator_notes text,
  created_at timestamptz not null default now()
);

-- ユーザー回答ログ
create table public.quiz_responses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  question_id uuid not null references public.quiz_questions(id),
  is_correct boolean not null,
  response_time_ms int not null,
  answered_at timestamptz not null default now()
);

-- ロジック破綻認定（ジャッジ投票）
create table public.logic_verdicts (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id),
  judge_id uuid not null references public.profiles(id),
  verdict text not null,
  reason text,
  created_at timestamptz not null default now(),
  unique(post_id, judge_id)
);

-- ストライク履歴
create table public.strikes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  strike_number int not null,
  reason_post_id uuid references public.posts(id),
  created_at timestamptz not null default now()
);

-- 異議申し立て
create table public.appeals (
  id uuid primary key default gen_random_uuid(),
  target_type text not null,
  target_id uuid not null,
  user_id uuid not null references public.profiles(id),
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

-- FCMデバイストークン
create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  fcm_token text not null,
  platform text not null,
  app_version text,
  updated_at timestamptz not null default now(),
  unique(user_id, fcm_token)
);

-- 通報
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id),
  target_type text not null,
  target_id uuid not null,
  reason text not null,
  detail text,
  status text not null default 'pending',
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

-- AIモデレーション判定ログ
create table public.moderation_checks (
  id uuid primary key default gen_random_uuid(),
  target_type text not null,
  target_id uuid not null,
  checked_content text not null,
  model text not null,
  verdict text not null,
  categories text[] not null default '{}',
  confidence numeric,
  created_at timestamptz not null default now()
);

-- ─────────────────────────────
-- auth.users 作成時に profiles を自動作成するトリガー
-- （design/system.md 3章「Auth」の1:1連携）
-- ─────────────────────────────
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username)
  values (new.id, coalesce(new.raw_user_meta_data->>'username', new.id::text));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────
-- RLS有効化（全テーブル）
-- ─────────────────────────────
alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.videos enable row level security;
alter table public.reposts enable row level security;
alter table public.endorsements enable row level security;
alter table public.battles enable row level security;
alter table public.battle_bets enable row level security;
alter table public.domain_scores enable row level security;
alter table public.quiz_generation_runs enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.quiz_responses enable row level security;
alter table public.logic_verdicts enable row level security;
alter table public.strikes enable row level security;
alter table public.appeals enable row level security;
alter table public.device_tokens enable row level security;
alter table public.reports enable row level security;
alter table public.moderation_checks enable row level security;

-- 公開読み取り/本人のみ書き込みの基本ポリシー
-- （quiz_generation_runs / moderation_checks は運用者・Edge Function[service role]のみが扱うため
--   クライアント向けポリシーを設けず、RLS有効化のみでデフォルト拒否とする）

create policy "profiles are publicly readable" on public.profiles for select using (true);
create policy "users can update own profile" on public.profiles for update using (auth.uid() = id);

create policy "posts are publicly readable" on public.posts for select using (true);
create policy "users can insert own posts" on public.posts for insert with check (auth.uid() = author_id);
create policy "users can update own posts" on public.posts for update using (auth.uid() = author_id);
create policy "users can delete own posts" on public.posts for delete using (auth.uid() = author_id);

create policy "videos are publicly readable" on public.videos for select using (true);
create policy "users can insert own videos" on public.videos for insert with check (auth.uid() = uploader_id);

create policy "reposts are publicly readable" on public.reposts for select using (true);
create policy "users can insert own reposts" on public.reposts for insert with check (auth.uid() = user_id);

create policy "endorsements are publicly readable" on public.endorsements for select using (true);
create policy "users can insert own endorsements" on public.endorsements for insert with check (auth.uid() = endorser_id);

create policy "battles are publicly readable" on public.battles for select using (true);
create policy "users can insert own battles" on public.battles for insert with check (auth.uid() = challenger_id);

create policy "battle_bets are publicly readable" on public.battle_bets for select using (true);
create policy "users can insert own battle_bets" on public.battle_bets for insert with check (auth.uid() = user_id);

create policy "domain_scores are publicly readable" on public.domain_scores for select using (true);

create policy "active quiz_questions are readable" on public.quiz_questions for select using (is_active = true);

create policy "users can read own quiz_responses" on public.quiz_responses for select using (auth.uid() = user_id);
create policy "users can insert own quiz_responses" on public.quiz_responses for insert with check (auth.uid() = user_id);

create policy "logic_verdicts are publicly readable" on public.logic_verdicts for select using (true);
create policy "users can insert own logic_verdicts" on public.logic_verdicts for insert with check (auth.uid() = judge_id);

create policy "users can read own strikes" on public.strikes for select using (auth.uid() = user_id);

create policy "users can read own appeals" on public.appeals for select using (auth.uid() = user_id);
create policy "users can insert own appeals" on public.appeals for insert with check (auth.uid() = user_id);

create policy "users can manage own device_tokens" on public.device_tokens for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "users can read own reports" on public.reports for select using (auth.uid() = reporter_id);
create policy "users can insert own reports" on public.reports for insert with check (auth.uid() = reporter_id);
