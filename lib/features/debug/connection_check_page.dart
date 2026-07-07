import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:postgrest/postgrest.dart';

import '../../core/supabase_client.dart';

enum _CheckStatus { idle, loading, success, warning, error }

class _CheckResult {
  _CheckResult(this.status, this.message);
  final _CheckStatus status;
  final String message;
}

/// design/system.md で定義された各バックエンドリソースへの疎通確認をまとめて表示する画面。
class ConnectionCheckPage extends StatefulWidget {
  const ConnectionCheckPage({super.key});

  @override
  State<ConnectionCheckPage> createState() => _ConnectionCheckPageState();
}

class _ConnectionCheckPageState extends State<ConnectionCheckPage> {
  _CheckResult _supabaseResult = _CheckResult(_CheckStatus.loading, '');
  _CheckResult _firebaseResult = _CheckResult(_CheckStatus.loading, '');

  @override
  void initState() {
    super.initState();
    _runAllChecks();
  }

  Future<void> _runAllChecks() async {
    await Future.wait([_checkSupabase(), _checkFirebase()]);
  }

  Future<void> _checkSupabase() async {
    setState(() => _supabaseResult = _CheckResult(_CheckStatus.loading, ''));
    try {
      // design/system.md 1章の profiles テーブルへの疎通確認。
      // マイグレーション未適用の場合はテーブル不在エラーになるが、
      // それ自体がSupabaseへの接続自体は成功していることの証明になる。
      final rows = await supabase.from('profiles').select().limit(1);
      setState(() {
        _supabaseResult = _CheckResult(
          _CheckStatus.success,
          'profiles テーブルに接続成功（${rows.length}件取得）',
        );
      });
    } on PostgrestException catch (e) {
      // テーブル未作成時、PostgRESTは 'PGRST205'（スキーマキャッシュに見つからない）
      // またはPostgres例外 '42P01'（relation does not exist）を返す。
      if (e.code == 'PGRST205' || e.code == '42P01') {
        setState(() {
          _supabaseResult = _CheckResult(
            _CheckStatus.warning,
            'Supabaseへの接続には成功しましたが、profilesテーブルが未作成です。\n'
            'design/system.md 1章のマイグレーションを適用してください。',
          );
        });
      } else {
        setState(() {
          _supabaseResult = _CheckResult(
            _CheckStatus.error,
            'Supabaseエラー: ${e.message} (code: ${e.code})',
          );
        });
      }
    } catch (e) {
      setState(() => _supabaseResult = _CheckResult(_CheckStatus.error, '接続に失敗しました: $e'));
    }
    debugPrint('[RENGA_CHECK] supabase ${_supabaseResult.status}: ${_supabaseResult.message}');
  }

  Future<void> _checkFirebase() async {
    setState(() => _firebaseResult = _CheckResult(_CheckStatus.loading, ''));
    try {
      // design/system.md 4章のRemote Configへの疎通確認（fetchAndActivateはネットワーク越しに
      // Firebaseサーバーからテンプレートを取得するため、実際の接続確認として機能する）。
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: Duration.zero,
        ),
      );
      await remoteConfig.fetchAndActivate();
      setState(() {
        _firebaseResult = _CheckResult(
          _CheckStatus.success,
          'Firebase Remote Configに接続成功（app: ${Firebase.app().options.appId}）',
        );
      });
    } catch (e) {
      setState(() => _firebaseResult = _CheckResult(_CheckStatus.error, '接続に失敗しました: $e'));
    }
    debugPrint('[RENGA_CHECK] firebase ${_firebaseResult.status}: ${_firebaseResult.message}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Renga — 基盤動作確認')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CheckCard(
            title: 'Supabase',
            subtitle: dotenv.env['SUPABASE_URL'] ?? '',
            result: _supabaseResult,
          ),
          const SizedBox(height: 12),
          _CheckCard(
            title: 'Firebase',
            subtitle: dotenv.env['FIREBASE_PROJECT_ID'] ?? '',
            result: _firebaseResult,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _runAllChecks,
            child: const Text('再接続テスト'),
          ),
        ],
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.title, required this.subtitle, required this.result});

  final String title;
  final String subtitle;
  final _CheckResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusIcon(result.status),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  if (result.message.isNotEmpty) Text(result.message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(_CheckStatus status) {
    switch (status) {
      case _CheckStatus.loading:
      case _CheckStatus.idle:
        return const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        );
      case _CheckStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green, size: 28);
      case _CheckStatus.warning:
        return const Icon(Icons.info, color: Colors.orange, size: 28);
      case _CheckStatus.error:
        return const Icon(Icons.error, color: Colors.red, size: 28);
    }
  }
}
