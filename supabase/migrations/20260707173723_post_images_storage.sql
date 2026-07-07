-- design/system.md 5章の画像投稿向けStorageバケット。
-- 投稿画像は `{userId}/{uuid}.{ext}` のパスで保存し、本人のみ書き込み可能とする。

insert into storage.buckets (id, name, public)
values ('post-images', 'post-images', true)
on conflict (id) do nothing;

create policy "post images are publicly readable"
on storage.objects for select
using (bucket_id = 'post-images');

create policy "users can upload their own post images"
on storage.objects for insert
with check (bucket_id = 'post-images' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "users can delete their own post images"
on storage.objects for delete
using (bucket_id = 'post-images' and auth.uid()::text = (storage.foldername(name))[1]);
