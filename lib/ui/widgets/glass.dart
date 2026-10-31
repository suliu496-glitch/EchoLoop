import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 毛玻璃面板。
///
/// 全应用所有「半透明 + 模糊」的外观都走这一个组件，保证观感统一，
/// 也方便统一调参数（需求 §6：圆角 12~16px、柔和阴影、层次清晰）。
///
/// 注意：按需求 §6 的规定，**视频画面区域不使用本组件**，
/// 模糊只出现在控制面板与列表上，避免字幕压在模糊层上看不清。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.radius = AppDimens.radiusLg,
    this.blur = AppDimens.blurPanel,
    this.strong = false,
    this.showBorder = true,
    this.showShadow = true,
    this.color,
    this.onTap,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final double blur;

  /// 强调态（更实的白底），用于高亮卡片
  final bool strong;

  final bool showBorder;
  final bool showShadow;
  final Color? color;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final borderRadius = BorderRadius.circular(radius);

    Widget panel = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? (strong ? palette.glassStrong : palette.glass),
            borderRadius: borderRadius,
            border: showBorder
                ? Border.all(color: palette.glassBorder, width: 1)
                : null,
            boxShadow: showShadow
                ? [
                    BoxShadow(
                      color: palette.shadow,
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      panel = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: panel,
      );
    }

    if (margin != null) {
      panel = Padding(padding: margin!, child: panel);
    }
    return panel;
  }
}

/// 毛玻璃上的图标按钮，用于播放页的小工具（微调、设 A/B 等）。
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
    this.activeColor,
    this.iconSize = 20,
    this.width,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color? activeColor;
  final double iconSize;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = activeColor ?? palette.accent;
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GlassPanel(
        width: width,
        radius: AppDimens.radiusSm,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        blur: AppDimens.blurBar,
        strong: active,
        color: active ? accent.withValues(alpha: 0.18) : null,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: active ? accent : palette.textPrimary,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: active ? accent : palette.textSecondary,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 面板内的小标题。
class GlassSectionTitle extends StatelessWidget {
  const GlassSectionTitle({
    super.key,
    required this.title,
    this.trailing,
    this.icon,
  });

  final String title;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: palette.accent),
          const SizedBox(width: 6),
        ],
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// 小圆角标签（格式标识、来源标识等）。
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = color ?? palette.accent;

    final chip = AnimatedContainer(
      duration: AppDimens.animFast,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? base.withValues(alpha: 0.18) : palette.glass,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        border: Border.all(
          color: selected ? base.withValues(alpha: 0.65) : palette.glassBorder,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: selected ? base : palette.textSecondary,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? base : palette.textPrimary,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: chip,
    );
  }
}
