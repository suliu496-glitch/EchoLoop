import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/utils/duration_utils.dart';

/// 单击显示控制，双击播放或暂停，退出只由专用按钮触发。
class FullscreenPlaybackSurface extends StatefulWidget {
  const FullscreenPlaybackSurface({
    super.key,
    required this.video,
    required this.controls,
    required this.positionMs,
    required this.durationMs,
    required this.onSeek,
    required this.onTogglePlay,
    required this.onExit,
    this.subtitle,
  });
  final Widget video;
  final Widget controls;
  final Widget? subtitle;
  final int positionMs;
  final int durationMs;
  final ValueChanged<int> onSeek;
  final VoidCallback onTogglePlay;
  final VoidCallback onExit;
  @override
  State<FullscreenPlaybackSurface> createState() =>
      _FullscreenPlaybackSurfaceState();
}

class _FullscreenPlaybackSurfaceState extends State<FullscreenPlaybackSurface> {
  Timer? _timer;
  bool _visible = true;
  double? _seekMs;
  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted && _seekMs == null) setState(() => _visible = false);
    });
  }

  void _tap() {
    setState(() => _visible = !_visible);
    if (_visible) {
      _scheduleHide();
    } else {
      _timer?.cancel();
    }
  }

  void _doubleTap() {
    widget.onTogglePlay();
    setState(() => _visible = true);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = math.max(1, widget.durationMs).toDouble();
    final position = (_seekMs ?? widget.positionMs.toDouble()).clamp(
      0.0,
      maxMs,
    );
    return GestureDetector(
      key: const ValueKey('fullscreen-surface'),
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      onDoubleTap: _doubleTap,
      child: Stack(
        children: [
          Positioned.fill(child: widget.video),
          if (widget.subtitle != null) widget.subtitle!,
          if (_visible)
            Positioned(
              key: const ValueKey('fullscreen-controls'),
              left: 0,
              right: 0,
              bottom: 12,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          DurationUtils.formatClock(position.round()),
                          style: const TextStyle(color: Colors.white),
                        ),
                        Expanded(
                          child: Slider(
                            value: position,
                            max: maxMs,
                            onChangeStart: (_) => _timer?.cancel(),
                            onChanged: widget.durationMs <= 0
                                ? null
                                : (value) {
                                    setState(() => _seekMs = value);
                                  },
                            onChangeEnd: widget.durationMs <= 0
                                ? null
                                : (value) {
                                    widget.onSeek(value.round());
                                    setState(() => _seekMs = null);
                                    _scheduleHide();
                                  },
                          ),
                        ),
                        Text(
                          DurationUtils.formatClock(widget.durationMs),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    widget.controls,
                  ],
                ),
              ),
            ),
          Positioned(
            top: 12,
            right: 12,
            child: IconButton.filledTonal(
              key: const ValueKey('exit-fullscreen'),
              tooltip: '退出全屏',
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              onPressed: widget.onExit,
              icon: const Icon(Icons.fullscreen_exit_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
