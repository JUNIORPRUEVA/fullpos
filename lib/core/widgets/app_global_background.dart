import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class AppGlobalBackground extends StatelessWidget {
  const AppGlobalBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(child: _GlobalBackgroundVisual()),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _GlobalBackgroundVisual extends StatelessWidget {
  const _GlobalBackgroundVisual();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.gradientStart,
                    AppColors.gradientMid,
                    AppColors.gradientEnd,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
