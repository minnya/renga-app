-- design/product.md 3.12節「基本エンゲージメント機能（いいね・コメント・リポスト・共有）」。
-- design/system.md 1章データモデル参照。

create table public.likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(post_id, user_id)
);

alter table public.likes enable row level security;

create policy "likes are publicly readable" on public.likes for select using (true);
create policy "users can like as themselves" on public.likes for insert with check (auth.uid() = user_id);
create policy "users can unlike their own like" on public.likes for delete using (auth.uid() = user_id);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

alter table public.comments enable row level security;

create policy "comments are publicly readable" on public.comments for select using (true);
create policy "users can comment as themselves" on public.comments for insert with check (auth.uid() = author_id);
create policy "users can delete their own comment" on public.comments for delete using (auth.uid() = author_id);

-- 既存の reposts テーブル（20260707173722_init_schema.sql）に delete policy が無く
-- un-repost できないため追加する。
create policy "users can remove their own repost" on public.reposts for delete using (auth.uid() = user_id);
