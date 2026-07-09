-- design/product.md 4章 / design/system.md 3章「Auth」: Googleサインインで新規登録した
-- ユーザーがusername等のプロフィール情報を入力しないままホームへ到達してしまう問題への対応。
-- `profiles.profile_completed` を追加し、Google新規登録時（`handle_new_user`トリガーが
-- `raw_user_meta_data->>'username'` を受け取れない、かつ `raw_app_meta_data->>'provider'` が
-- 'google' の場合）はfalseで作成する。ルーター側（lib/app/router.dart）がこのフラグを見て
-- `/complete-profile` へ強制リダイレクトする。
--
-- メール/パスワード登録は既存どおりusername未入力でもID由来のデフォルト値を許容する
-- （signup_page.dartの「未入力の場合は自動で割り当てられます」という既存仕様のため）ので、
-- 対象外（true のまま）とする。

alter table public.profiles
  add column profile_completed boolean not null default true;

-- 既存のGoogle経由ユーザーのうち、usernameがID由来のデフォルト値のまま
-- （＝プロフィール入力を一度も経ていない）ものを未完了として扱う。
update public.profiles p
set profile_completed = false
from auth.users u
where p.id = u.id
  and p.username = p.id::text
  and (u.raw_app_meta_data->>'provider') = 'google';

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, profile_completed)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', new.id::text),
    case
      -- サインアップ時にusernameが渡されていれば（メール登録でユーザーが入力済み）完了扱い。
      when coalesce(new.raw_user_meta_data->>'username', '') <> '' then true
      -- Google新規登録はusernameを渡せないため、プロフィール入力が必要な未完了状態で作成する。
      when (new.raw_app_meta_data->>'provider') = 'google' then false
      else true
    end
  );
  return new;
end;
$$;
