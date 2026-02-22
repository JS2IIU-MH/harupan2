import 'dart:ui';

/// アプリ全体の定数定義
class AppConstants {
  AppConstants._();

  // ── デザイン ──
  static const Color mainColor = Color(0xFF134A96);
  static const Color accentColor = Color(0xFFE4004F);

  // ── モデル ──
  static const String modelAssetPath = 'train/weights/best.onnx';
  static const int modelInputSize = 640;
  static const double confidenceThreshold = 0.38;
  static const double iouThreshold = 0.45;

  // ── ラベルと点数（YOLOv8 クラスインデックス順） ──
  // train/weights/best.onnx のメタデータに基づくクラス順:
  //   0: p05, 1: p10, 2: p15, 3: p25, 4: p30, 5: p20
  static const List<String> labels = [
    'p05', // 0
    'p10', // 1
    'p15', // 2
    'p25', // 3
    'p30', // 4
    'p20', // 5
  ];

  static const List<double> scores = [
    0.5, // p05
    1.0, // p10
    1.5, // p15
    2.5, // p25
    3.0, // p30
    2.0, // p20
  ];

  /// ラベルに対応する表示色
  static const List<Color> labelColors = [
    Color(0xFF4CAF50), // p05 - green
    Color(0xFF2196F3), // p10 - blue
    Color(0xFFFF9800), // p15 - orange
    Color(0xFF9C27B0), // p25 - purple
    Color(0xFFF44336), // p30 - red
    Color(0xFFE91E63), // p20 - pink
  ];

  // ── シェア ──
  static const String shareHashtag = '#harupan2';
}
