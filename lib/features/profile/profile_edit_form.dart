import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../core/supabase_client.dart';
import '../../l10n/gen/app_localizations.dart';
import 'profile_controller.dart';

/// design/product.md 3.10節「プロフィール詳細設定」の編集フォーム本体。
///
/// [ProfileEditSheet]（Profile画面の「編集」ボタンから開くボトムシート）と
/// `lib/features/settings/profile_edit_page.dart`（Settings画面経由のフルページ）の
/// 両方から共有される。保存ロジックは完全に共通で、[showCancelButton]のみで
/// 見た目（キャンセルボタンの有無）を切り替える。
///
/// 保存成功時は常に`Navigator.pop(context)`で呼び出し元（シート/ページ）を閉じる。
class ProfileEditForm extends ConsumerStatefulWidget {
  const ProfileEditForm({
    super.key,
    required this.userId,
    required this.profile,
    this.showCancelButton = true,
    this.showTitle = true,
  });

  final String userId;
  final Map<String, dynamic> profile;

  /// ボトムシートではキャンセルボタンを表示する（design/product.md 3.10節）。
  /// フルページでは通常の戻る操作がキャンセルに相当するため非表示にする。
  final bool showCancelButton;

  /// ボトムシートでは見出しテキストを表示するが、フルページではAppBarのタイトルが
  /// 既にその役割を果たすため非表示にできる。
  final bool showTitle;

  @override
  ConsumerState<ProfileEditForm> createState() => ProfileEditFormState();
}

class ProfileEditFormState extends ConsumerState<ProfileEditForm> {
  late final _displayNameController = TextEditingController(
    text: (widget.profile['display_name'] as String?) ?? '',
  );
  late final _bioController = TextEditingController(
    text: (widget.profile['bio'] as String?) ?? '',
  );
  late final _websiteUrlController = TextEditingController(
    text: (widget.profile['website_url'] as String?) ?? '',
  );
  late final _locationController = TextEditingController(
    text: (widget.profile['location'] as String?) ?? '',
  );
  bool _saving = false;
  String? _selectedAvatarPath;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _websiteUrlController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _handlePickAvatar() async {
    final l10n = AppLocalizations.of(context);
    try {
      final imagePicker = ImagePicker();
      final pickedFile = await imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (pickedFile == null) return;
      setState(() => _selectedAvatarPath = pickedFile.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileAvatarUploadError('$e'))),
      );
    }
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      if (_selectedAvatarPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.profileAvatarUploadProgress)),
        );

        final imageFile = XFile(_selectedAvatarPath!);
        final bytes = await imageFile.readAsBytes();
        final ext = _selectedAvatarPath!.split('.').last;

        final newAvatarUrl = await ref.read(profileControllerProvider).uploadAvatarImage(
              userId: widget.userId,
              bytes: bytes,
              fileExt: ext,
            );

        await supabase.from('profiles').update({
          'avatar_url': newAvatarUrl,
        }).eq('id', widget.userId);
      }

      await ref.read(profileControllerProvider).updateProfile(
            userId: widget.userId,
            displayName: _displayNameController.text.trim(),
            bio: _bioController.text.trim(),
            websiteUrl: _websiteUrlController.text.trim(),
            location: _locationController.text.trim(),
          );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileSaveSuccess)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileSaveError('$e'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final avatarUrl = widget.profile['avatar_url'] as String?;
    final displayName = (widget.profile['display_name'] as String?) ?? '';
    final username = (widget.profile['username'] as String?) ?? '';
    final fallbackName = displayName.isNotEmpty ? displayName : username;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle) ...[
          Center(
            child: Text(
              l10n.profileEditProfileButton,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
        ],
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: RengaColors.accent.withValues(alpha: 0.1),
                  border: Border.all(
                    color: RengaColors.accent.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: _selectedAvatarPath != null
                    ? ClipOval(
                        child: Image.file(File(_selectedAvatarPath!), fit: BoxFit.cover),
                      )
                    : (avatarUrl != null && avatarUrl.isNotEmpty
                        ? ClipOval(
                            child: Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildInitialAvatar(fallbackName, theme),
                            ),
                          )
                        : _buildInitialAvatar(fallbackName, theme)),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: FloatingActionButton.small(
                  onPressed: _handlePickAvatar,
                  backgroundColor: RengaColors.accent,
                  child: const Icon(Icons.camera_alt),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            l10n.profileAvatarChangeButton,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _displayNameController,
          decoration: InputDecoration(
            labelText: l10n.profileDisplayNameLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _bioController,
          decoration: InputDecoration(
            labelText: l10n.profileBioLabel,
            border: const OutlineInputBorder(),
          ),
          minLines: 3,
          maxLines: 6,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _websiteUrlController,
          decoration: InputDecoration(
            labelText: l10n.profileWebsiteUrlLabel,
            border: const OutlineInputBorder(),
            hintText: 'https://example.com',
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _locationController,
          decoration: InputDecoration(
            labelText: l10n.profileLocationLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : _handleSave,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(l10n.profileSaveButton),
              ),
            ),
            if (widget.showCancelButton) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: Text(l10n.profileCancelButton),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildInitialAvatar(String name, ThemeData theme) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Center(
      child: CircleAvatar(
        radius: 50,
        backgroundColor: RengaColors.accent.withValues(alpha: 0.2),
        child: Text(
          initial,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: RengaColors.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
