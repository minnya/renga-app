import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// design/system.md 11.2 で定義された SUPABASE_URL / SUPABASE_ANON_KEY を
/// .env から読み込み、Supabaseクライアントを初期化する。
Future<void> initSupabase() async {
  final url = dotenv.env['SUPABASE_URL'];
  final publishableKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (url == null || url.isEmpty || publishableKey == null || publishableKey.isEmpty) {
    throw StateError(
      'SUPABASE_URL / SUPABASE_ANON_KEY が .env に設定されていません。'
      '.env.example を参考に .env を作成してください。',
    );
  }

  await Supabase.initialize(url: url, publishableKey: publishableKey);
}

SupabaseClient get supabase => Supabase.instance.client;
