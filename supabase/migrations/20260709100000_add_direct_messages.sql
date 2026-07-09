-- design/product.md 3.17節「ダイレクトメッセージ（DM）」・design/system.md 15章参照。
-- 1対1DM。テキスト・画像・動画（Mux）の送信、既読、ブロック、自分側のみの論理削除に対応する。

create table public.dm_conversations (
  id uuid primary key default gen_random_uuid(),
  user_a_id uuid not null references public.profiles(id) on delete cascade,
  user_b_id uuid not null references public.profiles(id) on delete cascade,
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_a_id, user_b_id),
  check (user_a_id < user_b_id)
);

create index dm_conversations_user_a_idx on public.dm_conversations(user_a_id);
create index dm_conversations_user_b_idx on public.dm_conversations(user_b_id);

create table public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.dm_conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text,
  media_type text not null default 'text',
  media_url text,
  mux_playback_id text,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  check (media_type in ('text', 'image', 'video')),
  check (body is not null or media_url is not null or mux_playback_id is not null)
);

create index dm_messages_conversation_id_idx on public.dm_messages(conversation_id, created_at);

-- videos: DMメッセージへの動画添付にも対応するため、post_id/comment_idと同様に
-- dm_message_idを追加する（20260708160000のpost_id/comment_id二択パターンを三択に拡張）。
alter table public.videos
  drop constraint videos_post_or_comment_check;

alter table public.videos
  add column dm_message_id uuid references public.dm_messages(id) on delete cascade;

alter table public.videos
  add constraint videos_post_or_comment_or_dm_check
  check (
    (case when post_id is not null then 1 else 0 end
     + case when comment_id is not null then 1 else 0 end
     + case when dm_message_id is not null then 1 else 0 end) = 1
  );

create index videos_dm_message_id_idx on public.videos(dm_message_id);

create table public.dm_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table public.dm_conversation_deletions (
  conversation_id uuid not null references public.dm_conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  deleted_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

-- ─────────────────────────────
-- last_message_at の自動更新
-- ─────────────────────────────
-- dm_messages insert時にdm_conversations.last_message_atを更新し、一覧のソート・
-- プレビュー表示に使う（design/system.md 15.1節）。相手が会話を削除済みの場合は
-- 新着メッセージで一覧に復帰させる（design/system.md 15.1節「削除後に相手から新規
-- メッセージが届いた場合は復帰させる」）。
create or replace function public.handle_new_dm_message()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.dm_conversations
    set last_message_at = new.created_at
    where id = new.conversation_id;

  delete from public.dm_conversation_deletions
    where conversation_id = new.conversation_id;

  return new;
end;
$$;

create trigger dm_messages_after_insert
  after insert on public.dm_messages
  for each row execute function public.handle_new_dm_message();

-- ─────────────────────────────
-- 会話の取得/作成ヘルパーRPC
-- ─────────────────────────────
-- user_a_id/user_b_idの正規化（昇順）をクライアントに担わせずアトミックに行うため、
-- 会話の取得または新規作成をRPCとして提供する。
create or replace function public.get_or_create_dm_conversation(p_other_user_id uuid)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_a uuid;
  v_b uuid;
  v_conversation_id uuid;
begin
  if v_user_id is null then
    raise exception 'ログインが必要です';
  end if;
  if p_other_user_id = v_user_id then
    raise exception '自分自身との会話は作成できません';
  end if;

  if v_user_id < p_other_user_id then
    v_a := v_user_id;
    v_b := p_other_user_id;
  else
    v_a := p_other_user_id;
    v_b := v_user_id;
  end if;

  select id into v_conversation_id
    from public.dm_conversations
    where user_a_id = v_a and user_b_id = v_b;

  if v_conversation_id is null then
    insert into public.dm_conversations (user_a_id, user_b_id)
      values (v_a, v_b)
      returning id into v_conversation_id;
  end if;

  return v_conversation_id;
end;
$$;

grant execute on function public.get_or_create_dm_conversation(uuid) to authenticated;

-- ─────────────────────────────
-- RLS
-- ─────────────────────────────
alter table public.dm_conversations enable row level security;
alter table public.dm_messages enable row level security;
alter table public.dm_blocks enable row level security;
alter table public.dm_conversation_deletions enable row level security;

create policy "participants can read their conversations" on public.dm_conversations
  for select using (auth.uid() = user_a_id or auth.uid() = user_b_id);

-- insertは基本的にget_or_create_dm_conversation RPC（security definer）経由で行うため、
-- クライアントからの直接insertは自分が参加者になる行のみ許可する。
create policy "participants can create their conversations" on public.dm_conversations
  for insert with check (auth.uid() = user_a_id or auth.uid() = user_b_id);

create policy "participants can read their messages" on public.dm_messages
  for select using (
    exists (
      select 1 from public.dm_conversations c
      where c.id = conversation_id
        and (c.user_a_id = auth.uid() or c.user_b_id = auth.uid())
    )
  );

-- 送信は「自分が会話参加者」かつ「相手を自分がブロックしておらず、相手からもブロックされていない」
-- 場合のみ許可する（design/system.md 15.2節）。
create policy "participants can send messages if not blocked" on public.dm_messages
  for insert with check (
    auth.uid() = sender_id
    and exists (
      select 1 from public.dm_conversations c
      where c.id = conversation_id
        and (c.user_a_id = auth.uid() or c.user_b_id = auth.uid())
    )
    and not exists (
      select 1 from public.dm_blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = (
        select case when c.user_a_id = auth.uid() then c.user_b_id else c.user_a_id end
        from public.dm_conversations c where c.id = conversation_id
      ))
      or (b.blocked_id = auth.uid() and b.blocker_id = (
        select case when c.user_a_id = auth.uid() then c.user_b_id else c.user_a_id end
        from public.dm_conversations c where c.id = conversation_id
      ))
    )
  );

-- 既読更新: 受信者（送信者以外の参加者）のみread_atを更新できる。
create policy "recipient can mark messages as read" on public.dm_messages
  for update using (
    auth.uid() <> sender_id
    and exists (
      select 1 from public.dm_conversations c
      where c.id = conversation_id
        and (c.user_a_id = auth.uid() or c.user_b_id = auth.uid())
    )
  );

create policy "users can read their own blocks" on public.dm_blocks
  for select using (auth.uid() = blocker_id);
create policy "users can create their own blocks" on public.dm_blocks
  for insert with check (auth.uid() = blocker_id);
create policy "users can remove their own blocks" on public.dm_blocks
  for delete using (auth.uid() = blocker_id);

create policy "users can read their own conversation deletions" on public.dm_conversation_deletions
  for select using (auth.uid() = user_id);
create policy "users can create their own conversation deletions" on public.dm_conversation_deletions
  for insert with check (auth.uid() = user_id);
create policy "users can remove their own conversation deletions" on public.dm_conversation_deletions
  for delete using (auth.uid() = user_id);

-- Realtime（design/system.md 15.3節）: dm_messagesのpostgres_changesをクライアントが
-- 購読できるよう、supabase_realtime publicationへ追加する。
alter publication supabase_realtime add table public.dm_messages;

-- ─────────────────────────────
-- Storage: DM添付画像用バケット
-- ─────────────────────────────
insert into storage.buckets (id, name, public)
values ('dm-media', 'dm-media', true)
on conflict (id) do nothing;

create policy "dm-media is publicly readable" on storage.objects
  for select using (bucket_id = 'dm-media');
create policy "authenticated users can upload their own dm-media" on storage.objects
  for insert with check (
    bucket_id = 'dm-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
