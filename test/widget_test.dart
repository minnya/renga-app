import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:renga/core/supabase_client.dart';
import 'package:renga/main.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await dotenv.load(fileName: '.env');
    await initSupabase();
    // firebase_core はプラットフォームチャンネル未モックのためここでは初期化しない。
    // ConnectionCheckPage側のFirebaseチェックはtry/catchでエラー状態として扱われる想定。
  });

  testWidgets('ConnectionCheckPage shows Supabase and Firebase cards', (WidgetTester tester) async {
    await tester.pumpWidget(const RengaApp());

    expect(find.text('Renga — 基盤動作確認'), findsOneWidget);
    expect(find.text('Supabase'), findsOneWidget);
    expect(find.text('Firebase'), findsOneWidget);
  });
}
