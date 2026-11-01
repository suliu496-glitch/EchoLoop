import 'package:flutter/material.dart';

/// 媒体播放模式和高频断句操作，窄屏自动换行。
class MediaPlaybackControls extends StatelessWidget {
  const MediaPlaybackControls({
    super.key,
    required this.modeLabel,
    required this.modeIcon,
    required this.onChangeMode,
    required this.onAddSentence,
    required this.onPrevious,
    required this.onNext,
    this.onTogglePlay,
    this.isPlaying = false,
    this.dark = false,
    this.saving = false,
    this.compact = false,
  });

  final String modeLabel;
  final IconData modeIcon;
  final VoidCallback onChangeMode;
  final VoidCallback? onAddSentence;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onTogglePlay;
  final bool isPlaying;
  final bool dark;
  final bool saving;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: '上一条',
          color: color,
          constraints: compact
              ? const BoxConstraints(minWidth: 36, minHeight: 40)
              : null,
          padding: compact ? EdgeInsets.zero : null,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: onPrevious,
        ),
        if (dark)
          IconButton(
            tooltip: isPlaying ? '暂停' : '播放',
            color: color,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
            onPressed: onTogglePlay,
          ),
        TextButton.icon(
          key: const ValueKey('media-playback-mode'),
          style: TextButton.styleFrom(
            foregroundColor: color,
            padding: compact ? const EdgeInsets.symmetric(horizontal: 4) : null,
            minimumSize: compact ? const Size(0, 40) : null,
          ),
          onPressed: onChangeMode,
          icon: Icon(modeIcon),
          label: Text(modeLabel),
        ),
        if (!dark)
          FilledButton.tonalIcon(
            key: const ValueKey('add-sentence'),
            onPressed: saving ? null : onAddSentence,
            style: compact
                ? FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 40),
                  )
                : null,
            icon: const Icon(Icons.playlist_add_rounded, size: 19),
            label: Text(saving ? '保存中' : '添加断句'),
          ),
        IconButton(
          tooltip: '下一条',
          color: color,
          constraints: compact
              ? const BoxConstraints(minWidth: 36, minHeight: 40)
              : null,
          padding: compact ? EdgeInsets.zero : null,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: onNext,
        ),
      ],
    );
  }
}
