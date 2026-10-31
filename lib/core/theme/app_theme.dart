import 'package:flutter/material.dart';

/// 应用配色方案。
///
/// 用 [ThemeExtension] 承载而不是散落的常量，好处是浅色 / 深色两套值
/// 能跟着 `Theme.of(context)` 自动切换（需求 §6「深色模式跟随系统，提供深色毛玻璃变体」），
/// 动画过渡时也能被系统自动 lerp。
///
/// 关键设计原则（需求 §6）：
/// **视频画面区域保持纯净**，所以 [videoBackdrop] 是一个不带任何透明度的纯色，
/// 模糊只允许出现在控制面板与列表上，避免字幕压在模糊层上看不清。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.gradientTop,
    required this.gradientBottom,
    required this.glass,
    required this.glassStrong,
    required this.glassBorder,
    required this.accent,
    required this.accentSoft,
    required this.accentDeep,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.trackInactive,
    required this.danger,
    required this.success,
    required this.shadow,
    required this.videoBackdrop,
  });

  /// 页面底色
  final Color background;

  /// 背景渐变（上浅下深，营造毛玻璃的层次感）
  final Color gradientTop;
  final Color gradientBottom;

  /// 毛玻璃面板底色（半透明）
  final Color glass;

  /// 强调态毛玻璃（如高亮卡片）
  final Color glassStrong;

  /// 毛玻璃描边，用来勾出面板边缘
  final Color glassBorder;

  /// 强调色：天空蓝，用于片段选区、循环激活态、当前字幕、进度条已播部分
  final Color accent;
  final Color accentSoft;
  final Color accentDeep;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color divider;

  /// 进度条 / 滑块的未激活轨道
  final Color trackInactive;

  final Color danger;
  final Color success;

  /// 卡片柔和阴影
  final Color shadow;

  /// 视频区域底板，保持纯净不透明
  final Color videoBackdrop;

  // ---------------- 亮色：浅灰白基调 ----------------
  static const AppPalette light = AppPalette(
    background: Color(0xFFF5F6F8),
    gradientTop: Color(0xFFFCFDFE),
    gradientBottom: Color(0xFFEAEEF4),
    glass: Color(0xBFFFFFFF),
    glassStrong: Color(0xF2FFFFFF),
    glassBorder: Color(0xE6FFFFFF),
    accent: Color(0xFF3B82F6),
    accentSoft: Color(0x2E3B82F6),
    accentDeep: Color(0xFF2563EB),
    textPrimary: Color(0xFF1F2937),
    textSecondary: Color(0xFF6B7280),
    textTertiary: Color(0xFF9CA3AF),
    divider: Color(0x170F172A),
    trackInactive: Color(0x140F172A),
    danger: Color(0xFFEF4444),
    success: Color(0xFF10B981),
    shadow: Color(0x140F172A),
    videoBackdrop: Color(0xFF0B0D12),
  );

  // ---------------- 暗色：深灰底 + 提亮的天空蓝 ----------------
  static const AppPalette dark = AppPalette(
    background: Color(0xFF12141A),
    gradientTop: Color(0xFF191C24),
    gradientBottom: Color(0xFF0C0E13),
    glass: Color(0x1FFFFFFF),
    glassStrong: Color(0x38FFFFFF),
    glassBorder: Color(0x26FFFFFF),
    accent: Color(0xFF60A5FA),
    accentSoft: Color(0x3360A5FA),
    accentDeep: Color(0xFF3B82F6),
    textPrimary: Color(0xFFE8EAED),
    textSecondary: Color(0xFF9AA1AC),
    textTertiary: Color(0xFF6F7681),
    divider: Color(0x1FFFFFFF),
    trackInactive: Color(0x26FFFFFF),
    danger: Color(0xFFF87171),
    success: Color(0xFF34D399),
    shadow: Color(0x80000000),
    videoBackdrop: Color(0xFF000000),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? gradientTop,
    Color? gradientBottom,
    Color? glass,
    Color? glassStrong,
    Color? glassBorder,
    Color? accent,
    Color? accentSoft,
    Color? accentDeep,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? divider,
    Color? trackInactive,
    Color? danger,
    Color? success,
    Color? shadow,
    Color? videoBackdrop,
  }) {
    return AppPalette(
      background: background ?? this.background,
      gradientTop: gradientTop ?? this.gradientTop,
      gradientBottom: gradientBottom ?? this.gradientBottom,
      glass: glass ?? this.glass,
      glassStrong: glassStrong ?? this.glassStrong,
      glassBorder: glassBorder ?? this.glassBorder,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentDeep: accentDeep ?? this.accentDeep,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      divider: divider ?? this.divider,
      trackInactive: trackInactive ?? this.trackInactive,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      shadow: shadow ?? this.shadow,
      videoBackdrop: videoBackdrop ?? this.videoBackdrop,
    );
  }

  @override
  AppPalette lerp(covariant ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      gradientTop: Color.lerp(gradientTop, other.gradientTop, t)!,
      gradientBottom: Color.lerp(gradientBottom, other.gradientBottom, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassStrong: Color.lerp(glassStrong, other.glassStrong, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      trackInactive: Color.lerp(trackInactive, other.trackInactive, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      videoBackdrop: Color.lerp(videoBackdrop, other.videoBackdrop, t)!,
    );
  }
}

/// 便捷读取：`context.palette.accent`
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

/// 全局视觉常量：圆角、模糊强度、动效时长（需求 §6）。
class AppDimens {
  AppDimens._();

  static const double radiusSm = 12;
  static const double radiusMd = 14;
  static const double radiusLg = 16;
  static const double radiusXl = 22;

  static const double blurPanel = 18;
  static const double blurBar = 12;

  /// 动效统一 150~300ms，只跑 transform / opacity 以走 GPU
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 220);
  static const Duration animSlow = Duration(milliseconds: 300);

  static const double pagePadding = 16;
}

/// 主题装配。
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(AppPalette.light, Brightness.light);

  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette palette, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
    ).copyWith(
      primary: palette.accent,
      surface: palette.background,
      error: palette.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      splashFactory: InkSparkle.splashFactory,
      extensions: [palette],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: palette.textPrimary,
        titleTextStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.divider,
        thickness: 1,
        space: 1,
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: palette.textPrimary),
        bodyMedium: TextStyle(color: palette.textPrimary),
        bodySmall: TextStyle(color: palette.textSecondary),
        labelLarge: TextStyle(color: palette.textPrimary),
      ),
      // 统一底部弹出层外观，配合毛玻璃容器使用
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: false,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accent,
        inactiveTrackColor: palette.trackInactive,
        thumbColor: palette.accent,
        overlayColor: palette.accentSoft,
        trackHeight: 4,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.textPrimary,
        contentTextStyle: TextStyle(color: palette.background),
      ),
    );
  }
}
