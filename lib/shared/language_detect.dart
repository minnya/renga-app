/// design/product.md 3.12.1節「投稿・DMメッセージの自動翻訳」。
///
/// サーバー呼び出しなしのクライアント側簡易言語判定。現状サポートの表示言語がen/jaの2言語のため、
/// 日本語（ひらがな・カタカナ・漢字を含む）かそれ以外（ラテン文字主体＝英語）かの二値判定で足りる。
final _japaneseCharPattern = RegExp(
  r'[぀-ゟ゠-ヿ一-鿿]',
);

/// テキストの推定言語コードを返す（'ja' または 'en'）。
String detectTextLanguage(String text) {
  return _japaneseCharPattern.hasMatch(text) ? 'ja' : 'en';
}
