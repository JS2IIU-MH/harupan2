import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

import '../constants/app_constants.dart';
import '../models/detection_result.dart';

/// YOLOv8 モデルを使った物体検出サービス
class YoloService {
  OrtSession? _session;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// モデルを読み込みセッションを初期化する
  Future<void> initialize() async {
    if (_isInitialized) return;

    OrtEnv.instance.init();

    // アセット読み込みを別 Isolate で実行し、メインスレッドをブロックしない
    final rawAssetFile =
        await rootBundle.load(AppConstants.modelAssetPath);
    final bytes = await Isolate.run(() {
      return rawAssetFile.buffer.asUint8List();
    });

    final sessionOptions = OrtSessionOptions()
      ..setIntraOpNumThreads(4)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

    // OrtSession.fromBuffer は同期的で重い処理だが、ネイティブハンドルのため
    // Isolate に移せない。UI が描画される猶予を与えてからセッションを生成する。
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _session = OrtSession.fromBuffer(bytes, sessionOptions);

    sessionOptions.release();
    _isInitialized = true;
  }

  /// 前処理済み画像データから検出を行う
  ///
  /// [inputData] は [1, 3, 640, 640] 形式の Float32List
  /// [letterbox] はレターボックス情報（座標変換用）
  Future<List<DetectionResult>> detect(
    Float32List inputData,
    LetterboxInfo letterbox,
  ) async {
    if (!_isInitialized || _session == null) return [];

    final inputTensor = OrtValueTensor.createTensorWithDataList(
      inputData,
      [1, 3, AppConstants.modelInputSize, AppConstants.modelInputSize],
    );

    final runOptions = OrtRunOptions();
    final inputs = {_session!.inputNames.first: inputTensor};

    List<OrtValue?> outputs;
    try {
      final result = await _session!.runAsync(runOptions, inputs);
      if (result == null || result.isEmpty) return [];
      outputs = result;
    } catch (_) {
      // runAsync が使えない場合は同期版にフォールバック
      final result = _session!.run(runOptions, inputs);
      if (result.isEmpty) return [];
      outputs = result;
    }

    final outputTensor = outputs.first as OrtValueTensor;
    final outputData = outputTensor.value;

    // YOLOv8 出力をパースして DetectionResult に変換
    final detections = _parseOutput(outputData, letterbox);

    debugPrint(
      '[yolo] raw detections before NMS: ${detections.length}  '
      'after NMS: ${_nms(List.from(detections)).length}',
    );

    // リソース解放
    inputTensor.release();
    runOptions.release();
    for (final output in outputs) {
      output?.release();
    }

    return detections;
  }

  /// YOLOv8 出力 [1, (4+numClasses), numBoxes] を解析
  List<DetectionResult> _parseOutput(
    dynamic outputData,
    LetterboxInfo letterbox,
  ) {
    // outputData: List<List<List<double>>> shape [1, 10, 8400]
    final List rawBatch = outputData as List;
    final List rawFeatures = rawBatch[0] as List;

    final int numFeatures = rawFeatures.length; // 10
    final int numClasses = AppConstants.labels.length; // 6
    final int numBoxes = (rawFeatures[0] as List).length; // 8400

    assert(numFeatures == 4 + numClasses,
        'Model output features ($numFeatures) != 4 + $numClasses');

    final List<DetectionResult> results = [];
    final int inputSize = AppConstants.modelInputSize;
    double globalMaxScore = 0;

    for (int i = 0; i < numBoxes; i++) {
      // バウンディングボックス (model 座標系 0..640)
      final double cx = (rawFeatures[0] as List)[i].toDouble();
      final double cy = (rawFeatures[1] as List)[i].toDouble();
      final double w = (rawFeatures[2] as List)[i].toDouble();
      final double h = (rawFeatures[3] as List)[i].toDouble();

      // 最大クラスを検索
      double maxScore = 0;
      int maxClassIdx = 0;
      for (int c = 0; c < numClasses; c++) {
        final double score = (rawFeatures[4 + c] as List)[i].toDouble();
        if (score > maxScore) {
          maxScore = score;
          maxClassIdx = c;
        }
      }

      if (maxScore > globalMaxScore) globalMaxScore = maxScore;
      if (maxScore < AppConstants.confidenceThreshold) continue;

      // モデル座標からレターボックス除去 → 正規化座標 [0, 1] に変換
      final double x1 = ((cx - w / 2) - letterbox.padX) / (inputSize - 2 * letterbox.padX);
      final double y1 = ((cy - h / 2) - letterbox.padY) / (inputSize - 2 * letterbox.padY);
      final double x2 = ((cx + w / 2) - letterbox.padX) / (inputSize - 2 * letterbox.padX);
      final double y2 = ((cy + h / 2) - letterbox.padY) / (inputSize - 2 * letterbox.padY);

      results.add(DetectionResult(
        boundingBox: Rect.fromLTRB(
          x1.clamp(0.0, 1.0),
          y1.clamp(0.0, 1.0),
          x2.clamp(0.0, 1.0),
          y2.clamp(0.0, 1.0),
        ),
        classIndex: maxClassIdx,
        label: AppConstants.labels[maxClassIdx],
        confidence: maxScore,
        score: AppConstants.scores[maxClassIdx],
      ));
    }

    debugPrint('[parse] numBoxes=$numBoxes globalMaxScore=${globalMaxScore.toStringAsFixed(4)} passed=${results.length}');
    // NMS 適用
    return _nms(results);
  }

  /// Non-Maximum Suppression
  List<DetectionResult> _nms(List<DetectionResult> detections) {
    if (detections.isEmpty) return [];

    // 信頼度の降順でソート
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    final List<DetectionResult> kept = [];
    final suppressed = List<bool>.filled(detections.length, false);

    for (int i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;
      kept.add(detections[i]);

      for (int j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;
        if (_iou(detections[i].boundingBox, detections[j].boundingBox) >
            AppConstants.iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return kept;
  }

  /// IoU (Intersection over Union) を計算
  double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty || intersection.width <= 0 || intersection.height <= 0) {
      return 0.0;
    }

    final intersectionArea = intersection.width * intersection.height;
    final unionArea = a.width * a.height + b.width * b.height - intersectionArea;

    return unionArea > 0 ? intersectionArea / unionArea : 0.0;
  }

  /// リソースの解放
  void dispose() {
    _session?.release();
    _session = null;
    _isInitialized = false;
    OrtEnv.instance.release();
  }
}
