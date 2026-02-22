import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../providers/app_providers.dart';

/// カメラ切替・シェアボタンなどの操作 UI
class ControlButtons extends ConsumerWidget {
  final VoidCallback onShare;

  const ControlButtons({super.key, required this.onShare});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned(
      bottom: 32,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // カメラ切替ボタン
          _CircleButton(
            icon: Icons.cameraswitch,
            onPressed: () {
              ref.read(cameraDirectionProvider.notifier).toggle();
            },
          ),
          // シェアボタン
          _CircleButton(
            icon: Icons.share,
            onPressed: onShare,
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CircleButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppConstants.mainColor.withAlpha(180),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(
            icon,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}
