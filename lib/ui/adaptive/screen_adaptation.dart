import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

/// 屏幕形态判定与自适应容器。
///
/// 判定维度有三个，互相独立：
///
/// 1. **是否平板**：逻辑像素短边 >= 600dp。横向空间充裕，播放页可以
///    「左舞台 + 右字幕」两栏并排，视频也就有足够位置。
/// 2. **是否横屏**：宽度大于高度。手机横过来之后纵向空间骤降到 350dp 上下，
///    竖着把视频、时间轴、控制、字幕列表堆起来一定溢出，必须换左右分栏。
/// 3. **纵向空间是否紧张**：高度小于 520dp。这类屏幕要压缩间距与控件高度。
///
/// 为什么不干脆锁死手机竖屏来回避这个问题：看视频、跟读复述时横握更自然，
/// 锁方向只是把适配成本转嫁成用户的手腕成本。
/// 而且横屏的适配成本主要集中在播放页，其它页面本来就是
/// 「限宽居中」或「按可用宽度自适应列数」的结构，天然兼容横屏。
class ScreenAdaptation {
  ScreenAdaptation._();

  /// 平板的判定阈值（dp）。600 是 Android 官方推荐的平板分界值。
  static const double tabletShortestSide = 600;

  /// 「纵向空间紧张」的高度阈值（dp）。
  /// 手机横屏普遍落在 320~450dp，低于这个值时竖向排布一定放不下。
  static const double shortViewportHeight = 520;

  /// 内容最大宽度：平板上限宽居中，避免文字与控件被拉到两头。
  static const double contentMaxWidth = 900;

  static Size _sizeOf(BuildContext context) => MediaQuery.sizeOf(context);

  static bool isTablet(BuildContext context) =>
      _sizeOf(context).shortestSide >= tabletShortestSide;

  static bool isLandscape(BuildContext context) {
    final size = _sizeOf(context);
    return size.width > size.height;
  }

  /// 手机横屏：确实横过来了，但还不是平板。
  ///
  /// 这类设备既要分栏（高度不够堆叠），单栏又不能太宽（总宽度也有限），
  /// 所以布局方案与平板横屏不同。
  static bool isPhoneLandscape(BuildContext context) =>
      isLandscape(context) && !isTablet(context);

  /// 纵向空间紧张，需要压缩间距与控件高度。
  static bool isShortViewport(BuildContext context) =>
      _sizeOf(context).height < shortViewportHeight;

  /// 是否适合两栏布局（平板，或横屏手机）。
  static bool isWide(BuildContext context) {
    final size = _sizeOf(context);
    if (size.shortestSide >= tabletShortestSide) return true;
    // 横屏手机：宽高比明显大于 1 且宽度够，也走两栏
    return size.width > size.height && size.width >= 640;
  }

  /// 底部弹出面板的约束。
  ///
  /// 宽度：平板上不限宽的话，面板里一行按钮会横跨 1200dp，按钮之间隔着一整屏。
  /// 高度：横屏矮屏上必须限制，否则面板会顶到屏幕顶端，
  /// 而它又只有 9/16 屏高的默认上限，内容既显示不全也滚不动。
  static BoxConstraints sheetConstraints(BuildContext context) {
    if (!isShortViewport(context)) {
      return BoxConstraints(
        maxWidth: isTablet(context) ? 680 : double.infinity,
      );
    }
    return BoxConstraints(
      maxWidth: isTablet(context) ? 680 : double.infinity,
      maxHeight: _sizeOf(context).height * 0.9,
    );
  }

  /// 需要设定的屏幕方向。
  ///
  /// 全部放开。竖屏是主用姿态，但横过来也要能用（看视频、跟读时平放桌面）。
  /// 全屏播放视频时会另外单独锁横屏，那是播放器的正常行为。
  static List<DeviceOrientation> preferredOrientations(BuildContext context) =>
      DeviceOrientation.values;
}

/// 把内容限制在合理宽度内并居中。
///
/// 平板上不加约束的话，一行按钮会被拉到 1200dp 宽，按钮之间隔着一整屏，
/// 既不美观也难点。横屏手机同样受益：内容不会贴着两侧边缘。
class ConstrainedContent extends StatelessWidget {
  const ConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = ScreenAdaptation.contentMaxWidth,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
