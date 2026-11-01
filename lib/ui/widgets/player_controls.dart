import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/playback/playback_state.dart';
import 'glass.dart';

/// 主传输控件：微调按钮 + 播放/暂停。
class TransportControls extends StatelessWidget {
  const TransportControls({
    super.key,
    required this.isPlaying,
    required this.onTogglePlay,
    required this.onJump,
    this.enabled = true,
  });

  final bool isPlaying;
  final VoidCallback onTogglePlay;

  /// 传入秒数，负数后退、正数前进
  final ValueChanged<double> onJump;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        GlassIconButton(
          icon: Icons.fast_rewind,
          label: '-5s',
          onTap: enabled ? () => onJump(-5) : null,
          width: 56,
        ),
        GlassIconButton(
          icon: Icons.keyboard_double_arrow_left,
          label: '-2s',
          onTap: enabled ? () => onJump(-2) : null,
          width: 56,
        ),
        _PlayButton(isPlaying: isPlaying, onTap: enabled ? onTogglePlay : null),
        GlassIconButton(
          icon: Icons.keyboard_double_arrow_right,
          label: '+2s',
          onTap: enabled ? () => onJump(2) : null,
          width: 56,
        ),
        GlassIconButton(
          icon: Icons.fast_forward,
          label: '+5s',
          onTap: enabled ? () => onJump(5) : null,
          width: 56,
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.isPlaying, this.onTap});

  final bool isPlaying;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDimens.animNormal,
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.accent, palette.accentDeep],
          ),
          boxShadow: [
            BoxShadow(
              color: palette.accent.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 34,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 倍速选择条（需求 §3.1-2：一键切换、当前档位高亮）。
class SpeedSelector extends StatelessWidget {
  const SpeedSelector({
    super.key,
    required this.speed,
    required this.onChanged,
  });

  final double speed;
  final ValueChanged<double> onChanged;

  static String label(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}.0x' : '${value}x';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: AppConstants.speedPresets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final preset = AppConstants.speedPresets[index];
          final selected = (preset - speed).abs() < 0.001;
          return GlassChip(
            label: label(preset),
            selected: selected,
            onTap: () => onChanged(preset),
          );
        },
      ),
    );
  }
}

/// 循环按钮：激活时带呼吸动效，并显示剩余遍数（需求 §3.1-3 / §6）。
class LoopButton extends StatefulWidget {
  const LoopButton({
    super.key,
    required this.snapshot,
    required this.onStart,
    required this.onStop,
    required this.onOpenSettings,
  });

  final PlaybackSnapshot snapshot;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onOpenSettings;

  @override
  State<LoopButton> createState() => _LoopButtonState();
}

class _LoopButtonState extends State<LoopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant LoopButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final active = widget.snapshot.loopActive;
    if (active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final snapshot = widget.snapshot;
    final active = snapshot.loopActive;
    final finished = snapshot.status == PlaybackStatus.loopFinished;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 呼吸动效只改 transform / opacity，确保走 GPU 加速
        final t = active ? _controller.value : 0.0;
        final scale = 1 + t * 0.035;
        return Transform.scale(
          scale: scale,
          child: Opacity(opacity: active ? 0.88 + t * 0.12 : 1, child: child),
        );
      },
      child: GlassPanel(
        radius: AppDimens.radiusMd,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        strong: active,
        color: active ? palette.accent.withValues(alpha: 0.16) : null,
        onTap: () {
          if (!snapshot.loopActive) {
            widget.onStart();
          } else if (finished) {
            widget.onStart();
          } else {
            widget.onStop();
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              finished
                  ? Icons.refresh_rounded
                  : (active ? Icons.repeat_rounded : Icons.repeat),
              size: 20,
              color: active ? palette.accent : palette.textSecondary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    finished ? '再来一组' : (snapshot.loopButtonLabel),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? palette.accent : palette.textPrimary,
                    ),
                  ),
                  if (active && snapshot.loopRegion != null)
                    Text(
                      '${_sec(snapshot.loopRegion!.startMs)} → '
                      '${_sec(snapshot.loopRegion!.endMs)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: palette.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpenSettings,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _sec(int ms) {
    final s = ms / 1000.0;
    return '${s.toStringAsFixed(1)}s';
  }
}

/// 跟读停顿倒计时提示（需求 §3.3-8：界面显示「跟读中 3…2…1」）。
class GapCountdownBanner extends StatelessWidget {
  const GapCountdownBanner({
    super.key,
    required this.seconds,
    required this.total,
  });

  final int seconds;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GlassPanel(
      radius: AppDimens.radiusMd,
      strong: true,
      color: palette.accent.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_rounded, size: 18, color: palette.accent),
          const SizedBox(width: 8),
          Text(
            '跟读中 $seconds…',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: palette.accent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '共 $total 秒',
            style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
