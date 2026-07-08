-- design/product.md 3.12節「基本エンゲージメント機能」— コメントの返信スレッド化・メディア添付。
-- design/system.md 1章データモデル参照。

-- 返信スレッド（1階層）: 親コメントを指す自己参照カラム。nullはトップレベルコメント。
alter table public.comments
  add column parent_comment_id uuid references public.comments(id) on delete cascade;

-- コメント・返信への画像（複数可）・外部動画URL（Mux動画はvideos.comment_idで管理）添付。
alter table public.comments
  add column media_urls text[];
alter table public.comments
  add column external_video_url text;

create index if not exists comments_parent_comment_id_idx on public.comments(parent_comment_id);

-- videos: コメント/返信への動画添付に対応するため post_id をnullable化し、comment_idを追加。
-- どちらか一方（post_id / comment_id）が必須で、両方nullまたは両方非nullは不正。
alter table public.videos
  alter column post_id drop not null;

alter table public.videos
  add column comment_id uuid references public.comments(id) on delete cascade;

alter table public.videos
  add constraint videos_post_or_comment_check
  check (
    (post_id is not null and comment_id is null)
    or (post_id is null and comment_id is not null)
  );

create index if not exists videos_comment_id_idx on public.videos(comment_id);

-- RLS: comments/videosの既存ポリシーはpost_id/author_id等に依存しておらず、
-- 新規カラム追加のみでは既存のselect全公開・insert-own・delete-ownポリシーの変更は不要。
