import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../constants/app_constants.dart';
import '../models/detection_result.dart';

/// カメラ画像の前処理ユーティリティ
class ImageUtils {
  ImageUtils._();

  /// CameraImage を ONNX 入力用の Float32List に変換する（同期版）。
  ///
  /// 出力: [1, 3, 640, 640] CHW 形式, [0, 1] 正規化
  /// レターボックス処理を行い、アスペクト比を維持する。
  ///
  /// [sensorOrientation] はカメラセンサーの回転角度（0, 90, 180, 270）。
  /// Android 背面カメラは通常 90°、前面カメラは 270°。
  static (Float32List, LetterboxInfo) preprocess(
    CameraImage image, {
    int sensorOrientation = 0,
  }) {
    final params = _extractImageParams(image, sensorOrientation);
    return _preprocessFromParams(params);
  }

  /// CameraImage を別 Isolate で前処理する（非同期版）。
  ///
  /// メインスレッドのブロッキングを回避するために使用する。
  static Future<(Float32List, LetterboxInfo)> preprocessAsync(
    CameraImage image, {
    int sensorOrientation = 0,
  }) async {
    final params = _extractImageParams(image, sensorOrientation);
    return Isolate.run(() => _preprocessFromParams(params));
  }

  /// CameraImage からIsolateに渡せるプリミティブなパラメータを抽出する
  static _PreprocessParams _extractImageParams(
    CameraImage image,
    int sensorOrientation,
  ) {
    final bool isYuv = image.format.group == ImageFormatGroup.yuv420;

    if (isYuv) {
      return _PreprocessParams(
        isYuv: true,
        srcW: image.width,
        srcH: image.height,
        sensorOrientation: sensorOrientation,
        yBytes: Uint8List.fromList(image.planes[0].bytes),
        yRowStride: image.planes[0].bytesPerRow,
        uBytes: Uint8List.fromList(image.planes[1].bytes),
        uRowStride: image.planes[1].bytesPerRow,
        uPixelStride: image.planes[1].bytesPerPixel ?? 1,
        vBytes: Uint8List.fromList(image.planes[2].bytes),
        vRowStride: image.planes[2].bytesPerRow,
        vPixelStride: image.planes[2].bytesPerPixel ?? 1,
      );
    } else {
      return _PreprocessParams(
        isYuv: false,
        srcW: image.width,
        srcH: image.height,
        sensorOrientation: sensorOrientation,
        bgraBytes: Uint8List.fromList(image.planes[0].bytes),
        bgraBytesPerRow: image.planes[0].bytesPerRow,
      );
    }
  }

  /// パラメータから前処理を実行する（Isolate実行可能）
  static (Float32List, LetterboxInfo) _preprocessFromParams(
    _PreprocessParams params,
  ) {
    final int inputSize = AppConstants.modelInputSize;
    final int srcW = params.srcW;
    final int srcH = params.srcH;
    final int sensorOrientation = params.sensorOrientation;

    // センサー回転を考慮した有効寸法を計算
    final bool needsRotation =
        sensorOrientation == 90 || sensorOrientation == 270;
    final int effectiveW = needsRotation ? srcH : srcW;
    final int effectiveH = needsRotation ? srcW : srcH;

    // レターボックスのスケール・パディング計算（回転後の寸法に基づく）
    final double scale = min(inputSize / effectiveW, inputSize / effectiveH);
    final int newW = (effectiveW * scale).round();
    final int newH = (effectiveH * scale).round();
    final int padX = (inputSize - newW) ~/ 2;
    final int padY = (inputSize - newH) ~/ 2;

    final letterbox = LetterboxInfo(
      scale: scale,
      padX: padX,
      padY: padY,
      originalWidth: effectiveW,
      originalHeight: effectiveH,
    );

    // CHW 形式の float 配列を作成（灰色パディング 114/255 ≈ 0.447）
    final int totalPixels = inputSize * inputSize;
    final data = Float32List(3 * totalPixels);
    const double padValue = 114.0 / 255.0;
    for (int i = 0; i < data.length; i++) {
      data[i] = padValue;
    }

    // フォーマット別に変換
    if (params.isYuv) {
      _processYUV420FromParams(
          params, data, inputSize, srcW, srcH, newW, newH, padX, padY, scale,
          sensorOrientation);
    } else {
      _processBGRAFromParams(
          params, data, inputSize, srcW, srcH, newW, newH, padX, padY, scale,
          sensorOrientation);
    }

    return (data, letterbox);
  }

  /// 出力先座標 (dx, dy) をセンサー座標系の (sx, sy) にマッピングする。
  ///
  /// スケーリングとセンサー回転を考慮して変換を行う。
  static (int, int) _mapToSource(
    int dx,
    int dy,
    double scale,
    int srcW,
    int srcH,
    int sensorOrientation,
  ) {
    // まずスケールを戻して回転後の画像座標にマッピング
    final double effX = dx / scale;
    final double effY = dy / scale;

    double srcXf, srcYf;
    switch (sensorOrientation) {
      case 90:
        // 90°CW: (effX, effY) → src(effY, srcH - 1 - effX)
        srcXf = effY;
        srcYf = (srcH - 1) - effX;
      case 270:
        // 270°CW (= 90°CCW): (effX, effY) → src(srcW - 1 - effY, effX)
        srcXf = (srcW - 1) - effY;
        srcYf = effX;
      case 180:
        srcXf = (srcW - 1) - effX;
        srcYf = (srcH - 1) - effY;
      default:
        srcXf = effX;
        srcYf = effY;
    }

    return (
      srcXf.round().clamp(0, srcW - 1),
      srcYf.round().clamp(0, srcH - 1),
    );
  }

  /// YUV420 (Android) の処理
  static void _processYUV420(
    CameraImage image,
    Float32List data,
    int inputSize,
    int srcW,
    int srcH,
    int newW,
    int newH,
    int padX,
    int padY,
    double scale,
    int sensorOrientation,
  ) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final int yRowStride = yPlane.bytesPerRow;
    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final int totalPixels = inputSize * inputSize;

    for (int dy = 0; dy < newH; dy++) {
      for (int dx = 0; dx < newW; dx++) {
        // 回転を考慮してセンサー座標系にマッピング
        final (int sx, int sy) =
            _mapToSource(dx, dy, scale, srcW, srcH, sensorOrientation);
        final int uvSy = sy >> 1;
        final int uvSx = sx >> 1;

        // YUV 値の読み取り
        final int yVal = yPlane.bytes[sy * yRowStride + sx];
        final int uVal =
            uPlane.bytes[uvSy * uvRowStride + uvSx * uvPixelStride];
        final int vVal = vPlane.bytes[
            uvSy * vPlane.bytesPerRow + uvSx * (vPlane.bytesPerPixel ?? 1)];

        // YUV → RGB 変換
        final double r =
            (yVal + 1.370705 * (vVal - 128)).clamp(0, 255) / 255.0;
        final double g =
            (yVal - 0.698001 * (vVal - 128) - 0.337633 * (uVal - 128))
                    .clamp(0, 255) /
                255.0;
        final double b =
            (yVal + 1.732446 * (uVal - 128)).clamp(0, 255) / 255.0;

        // CHW 形式で書き込み
        final int tx = padX + dx;
        final int ty = padY + dy;
        final int pixelIdx = ty * inputSize + tx;
        data[pixelIdx] = r; // R channel
        data[totalPixels + pixelIdx] = g; // G channel
        data[2 * totalPixels + pixelIdx] = b; // B channel
      }
    }
  }

  /// YUV420 の処理（Isolate対応版 - _PreprocessParams から処理）
  static void _processYUV420FromParams(
    _PreprocessParams params,
    Float32List data,
    int inputSize,
    int srcW,
    int srcH,
    int newW,
    int newH,
    int padX,
    int padY,
    double scale,
    int sensorOrientation,
  ) {
    final yBytes = params.yBytes!;
    final uBytes = params.uBytes!;
    final vBytes = params.vBytes!;
    final int yRowStride = params.yRowStride!;
    final int uvRowStride = params.uRowStride!;
    final int uvPixelStride = params.uPixelStride!;
    final int vRowStride = params.vRowStride!;
    final int vPixelStride = params.vPixelStride!;

    final int totalPixels = inputSize * inputSize;

    for (int dy = 0; dy < newH; dy++) {
      for (int dx = 0; dx < newW; dx++) {
        final (int sx, int sy) =
            _mapToSource(dx, dy, scale, srcW, srcH, sensorOrientation);
        final int uvSy = sy >> 1;
        final int uvSx = sx >> 1;

        final int yVal = yBytes[sy * yRowStride + sx];
        final int uVal = uBytes[uvSy * uvRowStride + uvSx * uvPixelStride];
        final int vVal = vBytes[uvSy * vRowStride + uvSx * vPixelStride];

        final double r =
            (yVal + 1.370705 * (vVal - 128)).clamp(0, 255) / 255.0;
        final double g =
            (yVal - 0.698001 * (vVal - 128) - 0.337633 * (uVal - 128))
                    .clamp(0, 255) /
                255.0;
        final double b =
            (yVal + 1.732446 * (uVal - 128)).clamp(0, 255) / 255.0;

        final int tx = padX + dx;
        final int ty = padY + dy;
        final int pixelIdx = ty * inputSize + tx;
        data[pixelIdx] = r;
        data[totalPixels + pixelIdx] = g;
        data[2 * totalPixels + pixelIdx] = b;
      }
    }
  }

  /// BGRA8888 (iOS) の処理
  static void _processBGRA(
    CameraImage image,
    Float32List data,
    int inputSize,
    int srcW,
    int srcH,
    int newW,
    int newH,
    int padX,
    int padY,
    double scale,
    int sensorOrientation,
  ) {
    final plane = image.planes[0];
    final int bytesPerRow = plane.bytesPerRow;
    final bytes = plane.bytes;

    final int totalPixels = inputSize * inputSize;

    for (int dy = 0; dy < newH; dy++) {
      for (int dx = 0; dx < newW; dx++) {
        // 回転を考慮してセンサー座標系にマッピング
        final (int sx, int sy) =
            _mapToSource(dx, dy, scale, srcW, srcH, sensorOrientation);

        // BGRA の読み取り
        final int srcIdx = sy * bytesPerRow + sx * 4;
        final double b = bytes[srcIdx] / 255.0;
        final double g = bytes[srcIdx + 1] / 255.0;
        final double r = bytes[srcIdx + 2] / 255.0;
        // A は無視

        // CHW 形式で書き込み
        final int tx = padX + dx;
        final int ty = padY + dy;
        final int pixelIdx = ty * inputSize + tx;
        data[pixelIdx] = r;
        data[totalPixels + pixelIdx] = g;
        data[2 * totalPixels + pixelIdx] = b;
      }
    }
  }

  /// BGRA8888 の処理（Isolate対応版）
  static void _processBGRAFromParams(
    _PreprocessParams params,
    Float32List data,
    int inputSize,
    int srcW,
    int srcH,
    int newW,
    int newH,
    int padX,
    int padY,
    double scale,
    int sensorOrientation,
  ) {
    final bytes = params.bgraBytes!;
    final int bytesPerRow = params.bgraBytesPerRow!;

    final int totalPixels = inputSize * inputSize;

    for (int dy = 0; dy < newH; dy++) {
      for (int dx = 0; dx < newW; dx++) {
        final (int sx, int sy) =
            _mapToSource(dx, dy, scale, srcW, srcH, sensorOrientation);

        final int srcIdx = sy * bytesPerRow + sx * 4;
        final double b = bytes[srcIdx] / 255.0;
        final double g = bytes[srcIdx + 1] / 255.0;
        final double r = bytes[srcIdx + 2] / 255.0;

        final int tx = padX + dx;
        final int ty = padY + dy;
        final int pixelIdx = ty * inputSize + tx;
        data[pixelIdx] = r;
        data[totalPixels + pixelIdx] = g;
        data[2 * totalPixels + pixelIdx] = b;
      }
    }
  }
}

/// Isolateに渡すための前処理パラメータ
class _PreprocessParams {
  final bool isYuv;
  final int srcW;
  final int srcH;
  final int sensorOrientation;

  // YUV420 用
  final Uint8List? yBytes;
  final int? yRowStride;
  final Uint8List? uBytes;
  final int? uRowStride;
  final int? uPixelStride;
  final Uint8List? vBytes;
  final int? vRowStride;
  final int? vPixelStride;

  // BGRA 用
  final Uint8List? bgraBytes;
  final int? bgraBytesPerRow;

  _PreprocessParams({
    required this.isYuv,
    required this.srcW,
    required this.srcH,
    required this.sensorOrientation,
    this.yBytes,
    this.yRowStride,
    this.uBytes,
    this.uRowStride,
    this.uPixelStride,
    this.vBytes,
    this.vRowStride,
    this.vPixelStride,
    this.bgraBytes,
    this.bgraBytesPerRow,
  });
}
