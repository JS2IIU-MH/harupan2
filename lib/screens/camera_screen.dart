import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/app_constants.dart';
import '../providers/app_providers.dart';
import '../services/image_utils.dart';
import '../widgets/bounding_box_overlay.dart';
import '../widgets/control_buttons.dart';
import '../widgets/score_overlay.dart';

/// メインのカメラ画面
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  final _screenshotController = ScreenshotController();
  bool _isProcessing = false;
  bool _isStreaming = false;
  bool _isYoloReady = false;
  bool _didLogFirstFrame = false;
  CameraController? _activeController;
  int _sensorOrientation = 0;

  /// フレームスロットリング用：最小処理間隔
  static const _minFrameInterval = Duration(milliseconds: 100);
  DateTime _lastProcessedTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[CameraScreen] initState');
    _initializeYolo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // アプリがバックグラウンドに移った場合ストリーミングを停止
    if (state == AppLifecycleState.inactive) {
      _stopStream();
    }
  }

  Future<void> _initializeYolo() async {
    try {
      debugPrint('[YOLO] initialize start');
      final yolo = ref.read(yoloServiceProvider);
      await yolo.initialize();
      _isYoloReady = true;
      debugPrint('[YOLO] initialize done');
    } catch (e) {
      debugPrint('YOLO initialization error: $e');
    }
  }

  /// カメラストリームを開始
  void _startStream(CameraController controller) {
    if (_isStreaming) return;
    _isStreaming = true;
    _activeController = controller;
    _sensorOrientation = controller.description.sensorOrientation;
    debugPrint('[stream] startStream sensor=${_sensorOrientation}°');

    controller.startImageStream((CameraImage image) {
      // ストリーム受信確認（最初の1回だけ）
      if (!_didLogFirstFrame) {
        _didLogFirstFrame = true;
        debugPrint('[stream] first frame: format=${image.format.group.name} ${image.width}x${image.height} isYoloReady=$_isYoloReady isProcessing=$_isProcessing');
      }

      if (_isProcessing || !_isYoloReady) return;

      // フレームスロットリング：前回の処理から最小間隔が経過していなければスキップ
      final now = DateTime.now();
      if (now.difference(_lastProcessedTime) < _minFrameInterval) return;
      _lastProcessedTime = now;

      _isProcessing = true;
      _processFrame(image).then((_) {
        _isProcessing = false;
      });
    });
  }

  /// カメラストリームを停止
  void _stopStream() {
    if (!_isStreaming) return;
    _isStreaming = false;
    try {
      _activeController?.stopImageStream();
    } catch (_) {
      // 既に停止済みの場合は無視
    }
    _activeController = null;
  }

  /// 1フレームの処理（前処理 → 推論 → 結果更新）
  Future<void> _processFrame(CameraImage image) async {
    final yolo = ref.read(yoloServiceProvider);
    if (!yolo.isInitialized) return;

    try {
      // 前処理（別 Isolate で実行してメインスレッドのブロッキングを回避）
      final (inputData, letterbox) = await ImageUtils.preprocessAsync(
        image,
        sensorOrientation: _sensorOrientation,
      );

      // 推論
      final detections = await yolo.detect(inputData, letterbox);

      debugPrint(
        '[detect] format=${image.format.group.name} '
        'size=${image.width}x${image.height} '
        'sensor=${_sensorOrientation}° '
        'letterbox(scale=${letterbox.scale.toStringAsFixed(3)}, '
        'pad=${letterbox.padX},${letterbox.padY}) '
        'detections=${detections.length}',
      );

      // 結果を更新（mounted チェック）
      if (mounted) {
        ref.read(detectionResultsProvider.notifier).update(detections);
      }
    } catch (e) {
      debugPrint('Detection error: $e');
    }
  }

  /// スクリーンショットを撮ってシェア
  Future<void> _share() async {
    try {
      final imageBytes = await _screenshotController.capture();
      if (imageBytes == null) return;

      final totalScore = ref.read(totalScoreProvider);
      final scoreText = totalScore.toStringAsFixed(1);

      // 一時ファイルに保存
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/harupan2_score.png');
      await file.writeAsBytes(imageBytes);

      // シェア
      await SharePlus.instance.share(
        ShareParams(
          text: '合計 $scoreText 点! ${AppConstants.shareHashtag}',
          files: [XFile(file.path)],
        ),
      );
    } catch (e) {
      debugPrint('Share error: $e');
    }
  }

  /// カメラ権限がない場合のダイアログ
  void _showPermissionDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('カメラの権限が必要です'),
        content: const Text(
          'このアプリではシールを認識するためにカメラを使用します。\n'
          '設定画面からカメラの使用を許可してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('設定を開く'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameraAsync = ref.watch(cameraControllerProvider);
    final detections = ref.watch(detectionResultsProvider);
    final totalScore = ref.watch(totalScoreProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: cameraAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppConstants.mainColor),
        ),
        error: (error, stack) {
          // カメラ権限エラーの場合
          if (error.toString().contains('permission') ||
              error.toString().contains('Permission')) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showPermissionDialog();
            });
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.camera_alt, color: Colors.white54, size: 64),
                const SizedBox(height: 16),
                Text(
                  'カメラを起動できません',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    // プロバイダをリフレッシュしてリトライ
                    ref.invalidate(cameraControllerProvider);
                  },
                  child: const Text('再試行'),
                ),
              ],
            ),
          );
        },
        data: (controller) {
          // ストリーム開始
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _startStream(controller);
          });

          // カメラプレビューの表示用アスペクト比を計算
          // previewSize はセンサー座標系（横向き）なので、
          // ポートレート表示時は width/height を入れ替える
          final previewSize = controller.value.previewSize;
          final double displayAspectRatio;
          if (previewSize != null) {
            displayAspectRatio = previewSize.height / previewSize.width;
          } else {
            displayAspectRatio = 1 / controller.value.aspectRatio;
          }

          return Screenshot(
            controller: _screenshotController,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // レイヤー 1: カメラプレビュー
                Center(
                  child: AspectRatio(
                    aspectRatio: displayAspectRatio,
                    child: CameraPreview(controller),
                  ),
                ),

                // レイヤー 2: バウンディングボックス（カメラプレビューと同じ領域に配置）
                Center(
                  child: AspectRatio(
                    aspectRatio: displayAspectRatio,
                    child: BoundingBoxOverlay(detections: detections),
                  ),
                ),

                // レイヤー 3: 合計点表示
                ScoreOverlay(totalScore: totalScore),

                // レイヤー 4: 操作 UI
                ControlButtons(onShare: _share),
              ],
            ),
          );
        },
      ),
    );
  }
}
