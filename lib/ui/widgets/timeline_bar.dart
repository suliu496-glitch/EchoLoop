import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/duration_utils.dart';
import '../../domain/playback/playback_state.dart';

/// 时间轴：**上下两条独立轨道**。
///
/// 上一版把「拖进度」和「框选片段」塞在同一条轨道上，靠一个「框选模式」按钮切换，
/// 结果是要么按钮太多，要么用户忘了自己在哪个模式里。现在拆成两条：
///
/// ```
///   ┌───────────选区轨（细，暗）───────────┐
///   │      ▓▓▓▓▓▓▓▓▓▓▓▓                   │  ← 左右拖动即框选，两端可拖
///   └─────────────────────────────────────┘
///   ┌───────────进度轨（粗，亮）───────────┐
///   │  ─────────●────────────              │  ← 点左右拖动即跳转
///   └─────────────────────────────────────┘
/// ```
///
/// 语义按位置天然区分，不需要模式，也不需要切换按钮。
///
/// 拖动过程只改本地预览值，松手才提交给引擎，这样界面完全跟手，
/// 又不会因为高频 seek 把播放内核打爆。
class TimelineBar extends StatefulWidget {
  const TimelineBar({
    super.key,
    required this.positionMs,
    required this.durationMs,
    required this.region,
    required this.snapEnabled,
    required this.snap,
    required this.onSeek,
    required this.regionChanged,
  });

  final int positionMs;
  final int durationMs;
  final LoopRegion? region;
  final bool snapEnabled;

  /// 吸附函数：传入毫秒返回吸附后的毫秒（由上层决定用不用字幕）
  final int Function(int ms) snap;

  final ValueChanged<int> onSeek;
  final void Function(int startMs, int endMs) regionChanged;

  /// 选区轨高度。比进度轨矮，视觉上从属，也减少误触
  static const double selectionTrackHeight = 34;

  /// 进度轨高度
  static const double progressTrackHeight = 36;

  static const double _handleHitRadius = 30;

  @override
  State<TimelineBar> createState() => _TimelineBarState();
}

enum _Gesture { none, seek, handleA, handleB, selecting }

class _TimelineBarState extends State<TimelineBar> {
  _Gesture _gesture = _Gesture.none;
  double _width = 0;

  int? _previewPositionMs;
  int? _previewStartMs;
  int? _previewEndMs;
  int? _selectionAnchorMs;

  bool _snapHit = false;
  String? _snapHint;

  double get _trackWidth => _width <= 0 ? 1 : _width;

  int _msFromX(double x) {
    final duration = widget.durationMs;
    if (duration <= 0) return 0;
    final ratio = (x / _trackWidth).clamp(0.0, 1.0);
    return (ratio * duration).round();
  }

  double _xFromMs(int ms) {
    final duration = widget.durationMs;
    if (duration <= 0) return 0;
    return (ms / duration).clamp(0.0, 1.0) * _trackWidth;
  }

  int get _displayPositionMs => _previewPositionMs ?? widget.positionMs;

  int get _displayStartMs => _previewStartMs ?? widget.region?.startMs ?? 0;

  int get _displayEndMs => _previewEndMs ?? widget.region?.endMs ?? 0;

  bool get _hasRegion => widget.region != null || _previewStartMs != null;

  // ------------------------------------------------------------------
  // 选区轨
  // ------------------------------------------------------------------

  void _onSelectionDragStart(DragStartDetails details) {
    final x = details.localPosition.dx;
    final region = widget.region;

    if (region != null) {
      final startX = _xFromMs(region.startMs);
      final endX = _xFromMs(region.endMs);
      final distanceToStart = (x - startX).abs();
      final distanceToEnd = (x - endX).abs();

      if (distanceToStart <= TimelineBar._handleHitRadius ||
          distanceToEnd <= TimelineBar._handleHitRadius) {
        _gesture =
            distanceToStart <= distanceToEnd ? _Gesture.handleA : _Gesture.handleB;
        setState(() {
          _previewStartMs = region.startMs;
          _previewEndMs = region.endMs;
          _snapHit = false;
          _snapHint = null;
        });
        _applyHandleDrag(x);
        return;
      }
    }

    // 空白处按下：从这一点开始拉一段新区间
    final anchor = _snapped(_msFromX(x));
    setState(() {
      _gesture = _Gesture.selecting;
      _selectionAnchorMs = anchor;
      _previewStartMs = anchor;
      _previewEndMs = anchor;
      _snapHit = false;
      _snapHint = null;
    });
  }

  void _onSelectionDragUpdate(DragUpdateDetails details) {
    final x = details.localPosition.dx;
    switch (_gesture) {
      case _Gesture.handleA:
      case _Gesture.handleB:
        _applyHandleDrag(x);
        break;
      case _Gesture.selecting:
        final anchor = _selectionAnchorMs;
        if (anchor == null) break;
        final snapped = _snapped(_msFromX(x));
        setState(() {
          _previewStartMs = snapped < anchor ? snapped : anchor;
          _previewEndMs = snapped < anchor ? anchor : snapped;
        });
        break;
      default:
        break;
    }
  }

  void _onSelectionDragEnd(DragEndDetails details) {
    final start = _previewStartMs;
    final end = _previewEndMs;
    switch (_gesture) {
      case _Gesture.handleA:
      case _Gesture.handleB:
        if (start != null && end != null && end - start >= 100) {
          widget.regionChanged(start, end);
        }
        break;
      case _Gesture.selecting:
        if (start != null && end != null && end - start >= 150) {
          widget.regionChanged(start, end);
        }
        break;
      default:
        break;
    }
    setState(() {
      _gesture = _Gesture.none;
      _previewStartMs = null;
      _previewEndMs = null;
      _selectionAnchorMs = null;
      _snapHit = false;
      _snapHint = null;
    });
  }

  void _applyHandleDrag(double x) {
    final raw = _msFromX(x);
    final snapped = _snapped(raw);
    final hit = widget.snapEnabled && snapped != raw;
    setState(() {
      _snapHit = hit;
      _snapHint = hit ? '已吸附到字幕边界' : null;
      if (_gesture == _Gesture.handleA) {
        final end = _previewEndMs ?? widget.region?.endMs ?? raw;
        _previewStartMs = snapped.clamp(0, end > 0 ? end - 100 : snapped);
      } else {
        final start = _previewStartMs ?? widget.region?.startMs ?? 0;
        _previewEndMs = snapped < start + 100 ? start + 100 : snapped;
      }
    });
  }

  int _snapped(int valueMs) {
    // 两端是明确的媒体边界，不能被附近字幕的吸附点带离 0 或片尾。
    if (valueMs <= 0) return 0;
    if (widget.durationMs > 0 && valueMs >= widget.durationMs) {
      return widget.durationMs;
    }
    return widget.snapEnabled ? widget.snap(valueMs) : valueMs;
  }

  // ------------------------------------------------------------------
  // 进度轨
  // ------------------------------------------------------------------

  void _onProgressStart(DragStartDetails details) {
    setState(() {
      _gesture = _Gesture.seek;
      _previewPositionMs = _msFromX(details.localPosition.dx);
    });
  }

  void _onProgressUpdate(DragUpdateDetails details) {
    if (_gesture != _Gesture.seek) return;
    setState(() => _previewPositionMs = _msFromX(details.localPosition.dx));
  }

  void _onProgressEnd(DragEndDetails details) {
    if (_gesture != _Gesture.seek) return;
    final target = _previewPositionMs;
    setState(() {
      _gesture = _Gesture.none;
      _previewPositionMs = null;
    });
    if (target != null) widget.onSeek(target);
  }

  void _onProgressTapUp(TapUpDetails details) {
    if (_gesture != _Gesture.none) return;
    widget.onSeek(_msFromX(details.localPosition.dx));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: TimelineBar.selectionTrackHeight,
              width: double.infinity,
              child: _buildSelectionTrack(context),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: TimelineBar.progressTrackHeight,
              width: double.infinity,
              child: _buildProgressTrack(context),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSelectionTrack(BuildContext context) {
    final palette = context.palette;
    final startX = _hasRegion ? _xFromMs(_displayStartMs) : 0.0;
    final endX = _hasRegion ? _xFromMs(_displayEndMs) : 0.0;
    final bandWidth = endX - startX;
    final regionLengthMs = _hasRegion ? _displayEndMs - _displayStartMs : 0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: _onSelectionDragStart,
      onHorizontalDragUpdate: _onSelectionDragUpdate,
      onHorizontalDragEnd: _onSelectionDragEnd,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 6,
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                color: palette.trackInactive.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),

          if (_hasRegion && bandWidth > 0)
            Positioned(
              left: startX,
              width: bandWidth,
              top: 6,
              child: Container(
                height: 22,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: palette.accent.withValues(alpha: 0.7),
                    width: 1.2,
                  ),
                ),
                alignment: Alignment.center,
                child: bandWidth > 70
                    ? Text(
                        '${(regionLengthMs / 1000).toStringAsFixed(1)}s',
                        style: TextStyle(
                          fontSize: 10,
                          color: palette.accent,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      )
                    : null,
              ),
            ),

          // 空状态引导：不用猜这里能干什么
          if (!_hasRegion)
            Positioned.fill(
              top: 6,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    '左右拖动，框出一段反复练',
                    style: TextStyle(fontSize: 11, color: palette.textTertiary),
                  ),
                ),
              ),
            ),

          if (_hasRegion) _buildHandle(context, startX, 'A'),
          if (_hasRegion) _buildHandle(context, endX, 'B'),

          if (_snapHint != null)
            Positioned(
              left: 0,
              right: 0,
              top: -2,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: palette.success,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _snapHint!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHandle(BuildContext context, double x, String label) {
    final palette = context.palette;
    final dragging = (_gesture == _Gesture.handleA && label == 'A') ||
        (_gesture == _Gesture.handleB && label == 'B');
    final color = _snapHit && dragging ? palette.success : palette.accent;

    return Positioned(
      // 让边缘把手完整留在触摸区域内，避免一半画在轨道之外。
      left: (x - 9).clamp(0.0, (_trackWidth - 18).clamp(0.0, double.infinity)),
      top: 2,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  height: 1.3,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              width: dragging ? 6 : 4,
              height: 17,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressTrack(BuildContext context) {
    final palette = context.palette;
    final positionX = _xFromMs(_displayPositionMs);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _onProgressTapUp,
      onHorizontalDragStart: _onProgressStart,
      onHorizontalDragUpdate: _onProgressUpdate,
      onHorizontalDragEnd: _onProgressEnd,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 15,
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: palette.trackInactive,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Positioned(
            left: 0,
            width: positionX,
            top: 15,
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Positioned(
            left: positionX - 7,
            top: 11,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: palette.accent, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间轴上方的一行读数：当前时间 / 总时长 / AB 时间。
class TimelineReadout extends StatelessWidget {
  const TimelineReadout({
    super.key,
    required this.positionMs,
    required this.durationMs,
    required this.region,
    this.onClearRegion,
  });

  final int positionMs;
  final int durationMs;
  final LoopRegion? region;
  final VoidCallback? onClearRegion;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final current = region;

    return Row(
      children: [
        Text(
          DurationUtils.formatClock(positionMs),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: palette.accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          ' / ${DurationUtils.formatClock(durationMs)}',
          style: TextStyle(
            fontSize: 12,
            color: palette.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const Spacer(),
        if (current != null)
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'A ${DurationUtils.formatClock(current.startMs)}'
                  '  B ${DurationUtils.formatClock(current.endMs)}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: palette.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (onClearRegion != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClearRegion,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: palette.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
