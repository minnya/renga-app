import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// design/product.md 3.1節「YouTubeアプリの共有シートに登場」/
/// design/system.md 5.3節「YouTube埋め込み・共有連携」。
///
/// YouTubeアプリの「共有」からRengaを共有先として選択すると、動画タイトル+URLの
/// プレーンテキストが `ACTION_SEND` インテントとして渡される
/// （Android側の受け口は `android/app/src/main/AndroidManifest.xml` の
/// `text/plain` intent-filter）。このクラスは `receive_sharing_intent` パッケージを介して
/// そのテキストを受信し、アプリ側（main.dart）へ通知する。
///
/// - アプリがフォアグラウンド/バックグラウンドで起動中に共有された場合は [sharedTextStream] で通知。
/// - 共有から新規プロセス起動された場合の初期値は [getInitialSharedText] で取得する。
///
/// Phase1はAndroidのみ対応。iOSは共有シートに登場させるためにネイティブの
/// Share Extension実装（App Groups経由でのデータ受け渡し）が別途必要なため、
/// Phase2で対応する（design/system.md 5.3節）。
class ShareIntentService {
  ShareIntentService({ReceiveSharingIntent? receiveSharingIntent})
    : _receiveSharingIntent = receiveSharingIntent ?? ReceiveSharingIntent.instance;

  final ReceiveSharingIntent _receiveSharingIntent;

  /// アプリ起動中（フォアグラウンド/バックグラウンド）に共有されたテキストのストリーム。
  /// 共有された `SharedMediaFile` のうち、テキストとして渡された `path` を取り出して流す。
  Stream<String> get sharedTextStream => _receiveSharingIntent.getMediaStream().map(
    _extractFirstSharedText,
  ).where((text) => text != null).cast<String>();

  /// アプリが共有インテントから新規起動された場合の初期共有テキストを取得する。
  /// 共有起点でない通常起動の場合は`null`を返す。
  Future<String?> getInitialSharedText() async {
    final media = await _receiveSharingIntent.getInitialMedia();
    return _extractFirstSharedText(media);
  }

  /// 一度処理した共有インテントを消費済みにする。
  /// （同じ共有テキストで再度 `getInitialSharedText` が呼ばれた際に重複処理しないため）
  Future<void> reset() => _receiveSharingIntent.reset();

  String? _extractFirstSharedText(List<SharedMediaFile> media) {
    for (final file in media) {
      if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
        return file.path;
      }
    }
    return null;
  }
}

/// アプリ全体で単一の[ShareIntentService]を共有するためのProvider。
/// main.dartのルートウィジェットから参照し、起動処理に組み込む。
final shareIntentServiceProvider = Provider<ShareIntentService>((ref) {
  return ShareIntentService();
});
