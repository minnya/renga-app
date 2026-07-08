-- design/product.md 3.3節「インテリジェンス・レイヤー・フィルター: 選択状態はローカル保存＋アカウント同期」用のカラム。
-- クライアント側の LayerFilter enum（all | top25 | top5）と対応する。
-- 更新は既存の「users can update own profile」ポリシー（20260707173722_init_schema.sql）に
-- 従い、本人のみ可能。

alter table public.profiles
  add column default_layer_filter text not null default 'all';

alter table public.profiles
  add constraint profiles_default_layer_filter_check
  check (default_layer_filter in ('all', 'top25', 'top5'));
