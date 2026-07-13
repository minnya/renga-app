import 'package:flutter/material.dart';

import '../core/supabase_client.dart';
import '../l10n/gen/app_localizations.dart';
import 'language_detect.dart';

/// design/product.md 3.12.1節「投稿・DMメッセージの自動翻訳」。
///
/// 本文の推定言語が現在の表示言語と異なる場合にのみ、本文の下に「Translate」ボタンを表示する。
/// タップすると[system.md 6.5節](design/system.md#65-テキスト翻訳)の`translate_text` Edge
/// Functionを呼び出し、翻訳結果に表示を差し替える。もう一度タップすると原文表示（Show
/// original）に戻す。翻訳結果はこのウィジェットのインスタンス内メモリにのみキャッシュし、
/// DBには保存しない。
class TranslatableText extends StatefulWidget {
  const TranslatableText({super.key, required this.text, this.style, this.linkColor});

  final String text;
  final TextStyle? style;

  /// 「Translate」「Show original」リンクの色。DMバブルなど背景色が濃い場合に指定する。
  /// 未指定時は`colorScheme.primary`を使う。
  final Color? linkColor;

  @override
  State<TranslatableText> createState() => _TranslatableTextState();
}

class _TranslatableTextState extends State<TranslatableText> {
  String? _translatedText;
  bool _showingTranslation = false;
  bool _isLoading = false;
  String? _error;

  String _resolveTargetLocale(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode == 'ja' ? 'ja' : 'en';
  }

  Future<void> _handleTap(String targetLocale) async {
    if (_showingTranslation) {
      setState(() => _showingTranslation = false);
      return;
    }

    if (_translatedText != null) {
      setState(() => _showingTranslation = true);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await supabase.functions.invoke(
        'translate_text',
        body: {'text': widget.text, 'target_locale': targetLocale},
      );
      final translated = (response.data as Map?)?['translated_text'] as String?;
      if (translated == null) {
        throw Exception('unexpected response');
      }
      if (!mounted) return;
      setState(() {
        _translatedText = translated;
        _showingTranslation = true;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '$error';
      });
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.translateError(_error ?? ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetLocale = _resolveTargetLocale(context);
    final detectedLocale = detectTextLanguage(widget.text);
    final showButton = detectedLocale != targetLocale;
    final l10n = AppLocalizations.of(context);

    final displayedText = _showingTranslation && _translatedText != null
        ? _translatedText!
        : widget.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(displayedText, style: widget.style),
        if (showButton)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: InkWell(
              onTap: _isLoading ? null : () => _handleTap(targetLocale),
              child: _isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _showingTranslation ? l10n.showOriginalButton : l10n.translateButton,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: widget.linkColor ?? Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}
