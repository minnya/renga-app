import 'package:flutter/material.dart';

/// design/product.md 3.11節「Settings（設定）画面」。
///
/// TODO: アカウント（ログアウト）・通知・表示設定・表示言語の各セクションを実装する。
/// 現時点ではルーティング疎通確認用のプレースホルダー。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings (WIP)')),
    );
  }
}
