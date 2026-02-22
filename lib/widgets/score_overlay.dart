import 'package:flutter/material.dart';

/// 合計点数を画面中央に半透明の大文字で表示するウィジェット
class ScoreOverlay extends StatelessWidget {
  final double totalScore;

  const ScoreOverlay({super.key, required this.totalScore});

  @override
  Widget build(BuildContext context) {
    // 小数点以下を表示するかどうか（.0 の場合は省略可）
    final scoreText = totalScore == totalScore.roundToDouble()
        ? '${totalScore.toStringAsFixed(1)}点'
        : '${totalScore.toStringAsFixed(1)}点';

    return Center(
      child: Text(
        scoreText,
        style: TextStyle(
          fontSize: 100,
          fontWeight: FontWeight.w900,
          color: Colors.white.withAlpha(200),
          shadows: const [
            Shadow(
              blurRadius: 12,
              color: Colors.black54,
              offset: Offset(2, 2),
            ),
          ],
        ),
      ),
    );
  }
}
