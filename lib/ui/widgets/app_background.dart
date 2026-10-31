import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 应用背景：浅灰白渐变 + 两团柔光。
///
/// 柔光不是装饰，是让上层的 [BackdropFilter] 有东西可以模糊；
/// 没有它的话毛玻璃面板会看起来像一块纯色卡片，层次感全丢。
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.gradientTop,
            palette.background,
            palette.gradientBottom,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: _SoftBlob(
              size: 300,
              color: palette.accent.withValues(alpha: isDark ? 0.22 : 0.30),
            ),
          ),
          Positioned(
            bottom: -140,
            left: -100,
            child: _SoftBlob(
              size: 340,
              color: palette.accentDeep.withValues(alpha: isDark ? 0.16 : 0.20),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _SoftBlob extends StatelessWidget {
  const _SoftBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}
