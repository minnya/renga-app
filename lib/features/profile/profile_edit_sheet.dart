import 'package:flutter/material.dart';

import 'profile_edit_form.dart';

/// design/product.md 3.10節「プロフィール詳細設定」。編集はこのボトムシートに集約し、
/// Profile画面本体は常に読み取り専用ビューのままとする。
///
/// 実際のフォームロジックは[ProfileEditForm]に集約されており、
/// `lib/features/settings/profile_edit_page.dart`（Settings経由のフルページ版）と共有する。
class ProfileEditSheet extends StatelessWidget {
  const ProfileEditSheet({super.key, required this.userId, required this.profile});

  final String userId;
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ProfileEditForm(userId: userId, profile: profile),
        ),
      ),
    );
  }
}
