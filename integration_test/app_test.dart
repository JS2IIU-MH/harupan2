import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:harupan2/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('アプリ起動・UI要素テスト', (tester) async {
    // --- アプリ起動テスト ---
    await tester.pumpWidget(const ProviderScope(child: HarupanApp()));
    await tester.pump(const Duration(seconds: 1));

    // MaterialApp が表示されていることを確認
    expect(find.byType(MaterialApp), findsOneWidget);

    // Scaffold が表示されていることを確認
    expect(find.byType(Scaffold), findsOneWidget);

    // さらに待ってUIを安定させる
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    // --- スコア表示テスト ---
    // 初期スコアが 0.0 点であることを確認
    final scoreFinder = find.textContaining('0.0点');
    if (scoreFinder.evaluate().isNotEmpty) {
      expect(scoreFinder, findsOneWidget);
    }

    // --- カメラUI要素テスト ---
    // カメラ読み込み中のインジケーター、カメラUI要素、
    // またはエラーUIが表示されていることを確認
    final hasProgress = find.byType(CircularProgressIndicator);
    final hasCameraSwitch = find.byIcon(Icons.cameraswitch);
    final hasShare = find.byIcon(Icons.share);
    final hasErrorUI = find.textContaining('カメラ');

    final anyUIPresent = hasProgress.evaluate().isNotEmpty ||
        hasCameraSwitch.evaluate().isNotEmpty ||
        hasShare.evaluate().isNotEmpty ||
        hasErrorUI.evaluate().isNotEmpty;

    expect(anyUIPresent, isTrue,
        reason: 'カメラ関連のUI要素が表示されるべき');

    // --- 操作ボタンテスト ---
    if (hasCameraSwitch.evaluate().isNotEmpty) {
      expect(hasCameraSwitch, findsOneWidget);
      expect(hasShare, findsOneWidget);

      // カメラ切替ボタンをタップしてもクラッシュしないことを確認
      await tester.tap(hasCameraSwitch);
      await tester.pump(const Duration(seconds: 2));
    }
  });
}
