import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:postgrest/postgrest.dart';

import 'core/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await initSupabase();
  runApp(const RengaApp());
}

class RengaApp extends StatelessWidget {
  const RengaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Renga',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const SupabaseCheckPage(),
    );
  }
}

enum _CheckStatus { idle, loading, success, schemaMissing, error }

class SupabaseCheckPage extends StatefulWidget {
  const SupabaseCheckPage({super.key});

  @override
  State<SupabaseCheckPage> createState() => _SupabaseCheckPageState();
}

class _SupabaseCheckPageState extends State<SupabaseCheckPage> {
  _CheckStatus _status = _CheckStatus.idle;
  String? _message;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() {
      _status = _CheckStatus.loading;
      _message = null;
    });

    try {
      // design/system.md 1章の profiles テーブルへの疎通確認。
      // マイグレーション未適用の場合はテーブル不在エラーになるが、
      // それ自体がSupabaseへの接続自体は成功していることの証明になる。
      final rows = await supabase.from('profiles').select().limit(1);
      setState(() {
        _status = _CheckStatus.success;
        _message = 'profiles テーブルに接続成功（${rows.length}件取得）';
      });
      debugPrint('[RENGA_CHECK] success: $_message');
    } on PostgrestException catch (e) {
      // テーブル未作成時、PostgRESTは 'PGRST205'（スキーマキャッシュに見つからない）
      // またはPostgres例外 '42P01'（relation does not exist）を返す。
      if (e.code == 'PGRST205' || e.code == '42P01') {
        setState(() {
          _status = _CheckStatus.schemaMissing;
          _message =
              'Supabaseへの接続には成功しましたが、profilesテーブルが未作成です。\n'
              'design/system.md 1章のマイグレーションを適用してください。';
        });
      } else {
        setState(() {
          _status = _CheckStatus.error;
          _message = 'Supabaseエラー: ${e.message} (code: ${e.code})';
        });
      }
      debugPrint('[RENGA_CHECK] $_status: $_message');
    } catch (e) {
      setState(() {
        _status = _CheckStatus.error;
        _message = '接続に失敗しました: $e';
      });
      debugPrint('[RENGA_CHECK] error: $_message');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Renga — 基盤動作確認')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Supabase URL:\n${dotenv.env['SUPABASE_URL']}', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              _buildStatusIcon(),
              const SizedBox(height: 16),
              if (_message != null)
                Text(_message!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _status == _CheckStatus.loading ? null : _checkConnection,
                child: const Text('再接続テスト'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (_status) {
      case _CheckStatus.loading:
      case _CheckStatus.idle:
        return const CircularProgressIndicator();
      case _CheckStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green, size: 48);
      case _CheckStatus.schemaMissing:
        return const Icon(Icons.info, color: Colors.orange, size: 48);
      case _CheckStatus.error:
        return const Icon(Icons.error, color: Colors.red, size: 48);
    }
  }
}
