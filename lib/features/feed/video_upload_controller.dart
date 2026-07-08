import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';

/// アップロードの進行状況。design/system.md 5.1節の状態遷移
/// （pending → uploading → processing → ready | errored）のうち、
/// クライアント側で観測できる範囲を表す。
enum VideoUploadStatus { idle, uploading, uploaded, error }

/// design/system.md 5.1節「動画アップロードフロー（Direct Upload）」を実装するコントローラ。
///
/// 1. Edge Function `create_mux_upload` を呼び出し、Mux Direct Upload用の署名付きURLと
///    `upload_id` を取得する。
/// 2. 取得したURLへ動画ファイルを直接PUTアップロードする（Supabaseやアプリサーバーを経由しない）。
/// 3. `videos` テーブルへ `status='uploading'` でレコードを作成する。
///
/// 実際のトランスコード完了・`status='ready'`への更新はMux Webhook（`mux_webhook` Edge Function）が
/// 非同期に行うため、本コントローラの責務はアップロード開始までとなる。
class VideoUploadController {
  VideoUploadController();

  /// 動画をギャラリーから選択する。キャンセル時は`null`。
  Future<XFile?> pickVideo() {
    return ImagePicker().pickVideo(source: ImageSource.gallery);
  }

  /// 動画アップロードフロー一式を実行する。
  ///
  /// [onProgress] にはPUTアップロードの進捗（0.0〜1.0の概算、バイト数ベース）を通知する。
  /// 戻り値は作成された `videos.id`。
  Future<String> uploadVideo({
    required XFile video,
    required String postId,
    required String uploaderId,
    void Function(double progress)? onProgress,
  }) async {
    // 1. Edge Function経由でMux Direct Upload URLを発行してもらう。
    //    Mux API Token はクライアントに一切露出させず、Edge Function側でのみ保持する
    //    （design/system.md 5.4節）。
    final uploadResponse = await supabase.functions.invoke('create_mux_upload');
    if (uploadResponse.status != 200) {
      throw StateError('動画アップロードURLの発行に失敗しました: ${uploadResponse.data}');
    }
    final data = uploadResponse.data as Map<String, dynamic>;
    final uploadUrl = data['upload_url'] as String;
    final muxUploadId = data['upload_id'] as String;

    // 2. videos テーブルへ status='uploading' でレコードを作成しておく。
    //    アップロード開始直後にレコードを持たせることで、フィード側で
    //    「処理中」プレースホルダーを表示できるようにする（system.md 5.1節）。
    final videoRow = await supabase
        .from('videos')
        .insert({
          'post_id': postId,
          'uploader_id': uploaderId,
          'mux_upload_id': muxUploadId,
          'status': 'uploading',
        })
        .select('id')
        .single();
    final videoId = videoRow['id'] as String;

    // 3. Mux Direct Upload URLへ動画バイナリをPUTする。
    //    帯域コストを避けるため、アプリサーバー（Edge Function）は経由しない。
    //    `http.put`はバイト単位の進捗を通知しないため、開始/完了の2値でonProgressへ通知する
    //    簡易実装とする（詳細な進捗表示が必要になった場合はStreamedRequestへの置き換えを検討）。
    onProgress?.call(0);
    final bytes = await video.readAsBytes();
    final response = await http.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': _guessContentType(video.name)},
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await supabase.from('videos').update({
        'status': 'errored',
        'error_message': 'アップロードに失敗しました (HTTP ${response.statusCode})',
      }).eq('id', videoId);
      throw StateError('動画アップロードに失敗しました (HTTP ${response.statusCode})');
    }
    onProgress?.call(1);

    return videoId;
  }

  String _guessContentType(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'mov':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'mp4':
      default:
        return 'video/mp4';
    }
  }
}
