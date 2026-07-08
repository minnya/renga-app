-- design/product.md 4章「Notification（Endorse獲得、バッジ実績解除、ストライク通知）」用のテーブル。
-- 通知を実際に生成するEdge Function等は本マイグレーションの対象外（画面とデータ取得の土台のみ）。

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  kind text not null, -- endorse_received | badge_unlocked | battle_resolved | strike_warning 等
  title text not null,
  body text,
  related_post_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.notifications enable row level security;

create policy "users can read own notifications" on public.notifications for select using (auth.uid() = user_id);
create policy "users can update own notifications" on public.notifications for update using (auth.uid() = user_id);
