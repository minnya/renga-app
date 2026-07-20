-- design/system.md「username必須化」: 投稿者名としてIDがそのまま表示される不具合を防ぐため、
-- handle_new_userのデフォルト値をraw idではなく非ID形式のランダムハンドルにする。
-- 既存のusername=id::textな行も同じ形式へ一括置換する。

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, locale)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data->>'username', ''),
      'user_' || substr(replace(new.id::text, '-', ''), 1, 8)
    ),
    case
      when new.raw_user_meta_data->>'locale' in ('en', 'ja') then new.raw_user_meta_data->>'locale'
      else 'en'
    end
  );
  return new;
end;
$$;

update public.profiles
set username = 'user_' || substr(replace(id::text, '-', ''), 1, 8)
where username = id::text;
