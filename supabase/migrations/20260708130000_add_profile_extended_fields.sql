-- design/product.md 3.10節「プロフィール詳細設定」。
-- Instagram/Xのプロフィール編集画面同等に、website_url（外部リンク1件）と
-- location（自由入力テキスト、位置情報の実測はしない）を編集可能項目として追加する。

alter table public.profiles
  add column website_url text;

alter table public.profiles
  add column location text;
