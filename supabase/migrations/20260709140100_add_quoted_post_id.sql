-- design/product.md 3.12節「引用リポスト」/ design/system.md 1章参照。
-- X(Twitter)の引用リポスト相当。単純リポスト（既存の`reposts`テーブル）とは別に、
-- `posts`に引用元投稿を指す`quoted_post_id`を追加し、コメント付きの新規投稿として表現する。

alter table public.posts
  add column quoted_post_id uuid references public.posts(id);

-- 既存の "posts are publicly readable" / "users can insert own posts" ポリシー
-- （20260707173722_init_schema.sql）がそのまま `quoted_post_id` にも適用されるため、
-- ポリシーの追加変更は不要。
