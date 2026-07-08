/// design/system.md 5.3節「YouTube埋め込み・共有連携」。
///
/// 投稿本文からYouTube動画URLを検出し、埋め込み再生に必要な動画IDを抽出するユーティリティ。
library;

/// `youtube.com/watch?v=`, `youtu.be/`, `youtube.com/shorts/`, `youtube.com/embed/` 等の
/// 主要なYouTube URL形式から動画ID（英数字・`-`・`_` からなる11文字）を抽出する正規表現。
final RegExp _youtubeUrlPattern = RegExp(
  r'(?:https?:\/\/)?(?:www\.|m\.)?(?:youtube\.com\/(?:watch\?v=|shorts\/|embed\/|live\/)|youtu\.be\/)([a-zA-Z0-9_-]{11})',
  caseSensitive: false,
);

/// テキスト中から最初に見つかったYouTube動画IDを返す。見つからなければ`null`。
String? extractYoutubeVideoId(String text) {
  final match = _youtubeUrlPattern.firstMatch(text);
  return match?.group(1);
}

/// テキスト中から最初に見つかったYouTube URL全体（マッチした部分文字列）を返す。
/// `posts.external_video_url` に原文のまま保存する用途。
String? extractYoutubeUrl(String text) {
  final match = _youtubeUrlPattern.firstMatch(text);
  return match?.group(0);
}

/// テキストにYouTube動画URLが含まれるかどうか。
bool containsYoutubeUrl(String text) => _youtubeUrlPattern.hasMatch(text);
