import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/detection_result.dart';

/// バウンディングボックスを描画する CustomPainter
class BoundingBoxPainter extends CustomPainter {
  final List<DetectionResult> detections;

  BoundingBoxPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final color = AppConstants.labelColors[detection.classIndex];

      // バウンディングボックスの矩形（正規化座標 → 画面座標）
      final rect = Rect.fromLTRB(
        detection.boundingBox.left * size.width,
        detection.boundingBox.top * size.height,
        detection.boundingBox.right * size.width,
        detection.boundingBox.bottom * size.height,
      );

      // 矩形の描画
      final boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRect(rect, boxPaint);

      // ラベル背景
      final labelText = '${detection.label} ${detection.score}点';
      final textSpan = TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final labelBgRect = Rect.fromLTWH(
        rect.left,
        rect.top - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );

      final bgPaint = Paint()
        ..color = color.withAlpha(200)
        ..style = PaintingStyle.fill;
      canvas.drawRect(labelBgRect, bgPaint);

      // ラベルテキスト
      textPainter.paint(
        canvas,
        Offset(rect.left + 4, rect.top - textPainter.height - 2),
      );
    }
  }

  @override
  bool shouldRepaint(BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}

/// バウンディングボックスのオーバーレイウィジェット
class BoundingBoxOverlay extends StatelessWidget {
  final List<DetectionResult> detections;

  const BoundingBoxOverlay({super.key, required this.detections});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: BoundingBoxPainter(detections: detections),
      child: const SizedBox.expand(),
    );
  }
}
