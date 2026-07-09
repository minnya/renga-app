import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

/// signup_page.dart（メール/パスワード登録）と complete_profile_page.dart
/// （Google新規登録直後のプロフィール完了画面, design/product.md 4章「Complete Profile」）
/// の両方から使う、username入力欄の共通ウィジェット。
///
/// 「メール登録と同じ画面でプロフィール登録させる」という要件（design/system.md 3章「Auth」）を
/// 満たすため、TextFormField自体をここに切り出し、両画面で同一のラベル・ヘルパーテキスト・
/// バリデーションを共有する。
class ProfileSetupUsernameField extends StatelessWidget {
  const ProfileSetupUsernameField({
    super.key,
    required this.controller,
    this.validator,
    this.autofocus = false,
    this.labelText,
    this.helperText,
  });

  final TextEditingController controller;
  final String? Function(String?)? validator;
  final bool autofocus;

  /// 未指定時はsignup_page.dartと同じ既定ラベル/ヘルパーを使う。
  /// complete_profile_page.dartのように「必須」文言に差し替えたい場合はここで上書きする。
  final String? labelText;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      decoration: InputDecoration(
        labelText: labelText ?? l10n.signupUsernameLabel,
        helperText: helperText ?? l10n.signupUsernameHelper,
      ),
      validator: validator,
    );
  }
}
