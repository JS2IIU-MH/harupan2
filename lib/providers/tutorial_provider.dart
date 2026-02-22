import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kTutorialCompleted = 'tutorial_completed';

/// チュートリアル完了済みかどうかを返す
final tutorialCompletedProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kTutorialCompleted) ?? false;
});

/// チュートリアル完了フラグを永続化する
Future<void> completeTutorial() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kTutorialCompleted, true);
}
