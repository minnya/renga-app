import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_state.dart';
import '../../l10n/gen/app_localizations.dart';
import '../profile/profile_controller.dart';
import '../profile/profile_edit_form.dart';

/// design/product.md 3.11節「Settings（設定）画面」のプロフィール編集サブページ。
///
/// Profile画面の「編集」ボタンから開く[ProfileEditSheet]（ボトムシート）と同じ編集ロジック
/// （[ProfileEditForm]）を再利用し、Settings経由でも同じ内容を編集できる導線を提供する
/// （3.10節・3.11節）。
class ProfileEditPage extends ConsumerWidget {
  const ProfileEditPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final currentUser = ref.watch(currentUserProvider);

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.profileEditProfileButton)),
        body: Center(child: Text(l10n.profileSignedOutMessage)),
      );
    }

    final profileAsync = ref.watch(profileProvider(currentUser.id));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileEditProfileButton)),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(l10n.profileLoadError('$error')),
        ),
        data: (profile) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ProfileEditForm(
            userId: currentUser.id,
            profile: profile,
            showCancelButton: false,
            showTitle: false,
          ),
        ),
      ),
    );
  }
}
