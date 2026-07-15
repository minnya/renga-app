-- videosテーブルに不足していたUPDATEポリシーを追加する。
-- video_upload_controller.dart はMuxアップロード失敗時に自分の videos 行の
-- status/error_message を更新するが、これまでUPDATEポリシーが存在せず
-- RLSにより0件更新（サイレントに失敗）となっていた。
-- uploader_id = auth.uid() かつ 現在status='uploading' → 更新後status='errored'
-- の遷移のみを許可し、Mux Webhook（service role）が管理する
-- mux_asset_id/mux_playback_id/status='ready'等への遷移はクライアントから行えないようにする。
create policy "users can mark own uploading video as errored"
  on public.videos
  for update
  using (auth.uid() = uploader_id and status = 'uploading')
  with check (auth.uid() = uploader_id and status = 'errored');
