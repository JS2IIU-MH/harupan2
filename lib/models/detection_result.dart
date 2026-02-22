import 'dart:ui';

/// 物体検出結果を表すデータクラス
class DetectionResult {
  /// 正規化座標 [0, 1] のバウンディングボックス
  final Rect boundingBox;

  /// YOLOv8 クラスインデックス (0-5)
  final int classIndex;

  /// ラベル名 (p05, p10, ...)
  final String label;

  /// 信頼度スコア (0-1)
  final double confidence;

  /// シールの点数 (0.5, 1.0, ...)
  final double score;

  const DetectionResult({
    required this.boundingBox,
    required this.classIndex,
    required this.label,
    required this.confidence,
    required this.score,
  });

  @override
  String toString() =>
      'DetectionResult($label, score=$score, conf=${confidence.toStringAsFixed(2)}, '
      'box=${boundingBox.left.toStringAsFixed(2)},${boundingBox.top.toStringAsFixed(2)},'
      '${boundingBox.right.toStringAsFixed(2)},${boundingBox.bottom.toStringAsFixed(2)})';
}

/// 前処理で生成されたレターボックス情報
class LetterboxInfo {
  final double scale;
  final int padX;
  final int padY;
  final int originalWidth;
  final int originalHeight;

  const LetterboxInfo({
    required this.scale,
    required this.padX,
    required this.padY,
    required this.originalWidth,
    required this.originalHeight,
  });
}
