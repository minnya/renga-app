-- design/product.md 3.11節「Settings（設定）画面」/ サインアップ画面での言語選択に対応。
-- サインアップ時にクライアントが`raw_user_meta_data->>'locale'`（'en'/'ja'のいずれか）を渡した場合、
-- profiles.localeへ反映する。未指定・不正値の場合は既存どおりデフォルト'en'のままにする。

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, locale)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', new.id::text),
    case
      when new.raw_user_meta_data->>'locale' in ('en', 'ja') then new.raw_user_meta_data->>'locale'
      else 'en'
    end
  );
  return new;
end;
$$;
