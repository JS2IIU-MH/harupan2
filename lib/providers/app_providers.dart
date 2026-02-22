import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/detection_result.dart';
import '../services/yolo_service.dart';

// ── YoloService（シングルトン） ──
final yoloServiceProvider = Provider<YoloService>((ref) {
  final service = YoloService();
  ref.onDispose(() => service.dispose());
  return service;
});

// ── カメラ方向 ──
class CameraDirectionNotifier extends Notifier<CameraLensDirection> {
  @override
  CameraLensDirection build() => CameraLensDirection.back;

  void toggle() {
    state = state == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
  }
}

final cameraDirectionProvider =
    NotifierProvider<CameraDirectionNotifier, CameraLensDirection>(
  CameraDirectionNotifier.new,
);

// ── カメラコントローラ ──
final cameraControllerProvider =
    FutureProvider.autoDispose<CameraController>((ref) async {
  final direction = ref.watch(cameraDirectionProvider);
  final cameras = await availableCameras();
  final camera = cameras.firstWhere(
    (c) => c.lensDirection == direction,
    orElse: () => cameras.first,
  );
  final controller = CameraController(
    camera,
    ResolutionPreset.medium,
    enableAudio: false,
    imageFormatGroup: ImageFormatGroup.yuv420,
  );
  await controller.initialize();
  ref.onDispose(() => controller.dispose());
  return controller;
});

// ── 検出結果 ──
class DetectionResultsNotifier extends Notifier<List<DetectionResult>> {
  @override
  List<DetectionResult> build() => [];

  void update(List<DetectionResult> results) {
    state = results;
  }
}

final detectionResultsProvider =
    NotifierProvider<DetectionResultsNotifier, List<DetectionResult>>(
  DetectionResultsNotifier.new,
);

// ── 合計点（検出結果から自動計算） ──
final totalScoreProvider = Provider<double>((ref) {
  final detections = ref.watch(detectionResultsProvider);
  return detections.fold<double>(0.0, (sum, d) => sum + d.score);
});
