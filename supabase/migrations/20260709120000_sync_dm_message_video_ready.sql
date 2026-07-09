-- design/system.md 15章「ダイレクトメッセージ（DM）」への動画送信対応。
--
-- `videos`テーブルはMux Webhook（`mux_webhook` Edge Function）が`status`/`mux_playback_id`を
-- 更新する。投稿・コメントは表示時に`videos`をネストselectして参照できるが、
-- `dm_messages`は`mux_playback_id`列を直接持つ非正規化構造のため、
-- `videos.dm_message_id`が紐づく行が`status='ready'`になったタイミングで
-- `dm_messages.mux_playback_id`へ反映するトリガーを追加する。

create or replace function public.sync_dm_message_video_ready()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.dm_message_id is not null and new.status = 'ready' then
    update public.dm_messages
      set mux_playback_id = new.mux_playback_id
      where id = new.dm_message_id;
  end if;
  return new;
end;
$$;

create trigger videos_after_update_sync_dm_message
  after update of status on public.videos
  for each row execute function public.sync_dm_message_video_ready();
