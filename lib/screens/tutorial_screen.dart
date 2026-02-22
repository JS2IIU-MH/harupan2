import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/app_constants.dart';
import '../providers/tutorial_provider.dart';
import 'camera_screen.dart';

/// 初回起動時に表示するチュートリアル画面（3 ページ）
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _cameraGranted = false;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  Future<void> _checkCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted && mounted) {
      setState(() => _cameraGranted = true);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// チュートリアル完了 → CameraScreen へ遷移
  Future<void> _finish() async {
    await completeTutorial();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const CameraScreen()),
    );
  }

  /// 次のページへ
  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// スキップ → 即完了
  Future<void> _skip() async => _finish();

  /// カメラ権限をリクエスト
  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted) {
      setState(() => _cameraGranted = true);
      _next();
    } else if (status.isPermanentlyDenied) {
      // 設定画面へ誘導
      _showSettingsDialog();
    }
  }

  void _showSettingsDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('カメラの権限が必要です'),
        content: const Text('設定画面からカメラの使用を許可してください。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('あとで'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // スキップボタン
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skip,
                child: Text(
                  'スキップ',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ),
            ),

            // ページ本体
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                physics: const ClampingScrollPhysics(),
                children: [
                  _CameraPermissionPage(
                    granted: _cameraGranted,
                    onRequest: _requestCamera,
                    onNext: _next,
                  ),
                  _TutorialPage(
                    icon: Icons.cameraswitch,
                    title: 'カメラの切り替え',
                    description:
                        '画面下のカメラ切替ボタンをタップすると、\nイン / アウトカメラを切り替えられます。',
                  ),
                  _TutorialPage(
                    icon: Icons.share,
                    title: 'SNS にシェア',
                    description:
                        '画面下のシェアボタンをタップすると、\nスコア付きスクリーンショットを\nSNS に共有できます。',
                  ),
                ],
              ),
            ),

            // ページインジケータ
            _PageIndicator(
              count: 3,
              current: _currentPage,
            ),
            const SizedBox(height: 16),

            // 下部ボタン
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32).copyWith(bottom: 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConstants.mainColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _currentPage < 2 ? _next : _finish,
                  child: Text(
                    _currentPage < 2 ? '次へ' : 'はじめる',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page 1: カメラ権限 ─────────────────────────────

class _CameraPermissionPage extends StatelessWidget {
  final bool granted;
  final VoidCallback onRequest;
  final VoidCallback onNext;

  const _CameraPermissionPage({
    required this.granted,
    required this.onRequest,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            granted ? Icons.check_circle : Icons.camera_alt,
            size: 100,
            color: granted ? Colors.green : AppConstants.mainColor,
          ),
          const SizedBox(height: 32),
          Text(
            'カメラを許可',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppConstants.mainColor,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            'シールを認識するためにカメラを使用します。\nカメラの使用を許可してください。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 32),
          if (!granted)
            OutlinedButton.icon(
              onPressed: onRequest,
              icon: const Icon(Icons.camera_alt),
              label: const Text('カメラを許可する'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppConstants.mainColor,
                side: const BorderSide(color: AppConstants.mainColor),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            )
          else
            Text(
              '許可済み ✓',
              style: TextStyle(
                fontSize: 16,
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── 汎用チュートリアルページ ────────────────────────

class _TutorialPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _TutorialPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 100, color: AppConstants.mainColor),
          const SizedBox(height: 32),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppConstants.mainColor,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

// ─── ページインジケータ（ドット） ──────────────────────

class _PageIndicator extends StatelessWidget {
  final int count;
  final int current;

  const _PageIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppConstants.mainColor : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
