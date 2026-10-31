import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/duration_utils.dart';
import '../../data/models/subtitle_models.dart';
import '../../domain/subtitles/subtitle_cue.dart';
import '../../providers/playback_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/subtitle_provider.dart';

/// 字幕列表（需求 §3.2-7）。
///
/// 三个关键行为：
/// 1. 跟随播放进度自动高亮当前句，并把当前句滚动到可视区中间；
/// 2. 点某句 → 跳到该句起点试听；
/// 3. 长按 / 点右侧图标 → 把该句设为 AB 片段并开始循环。
///
/// 自动滚动会在用户手动滑动时暂停 4 秒，避免「用户想往回看，列表却一直往下拽」。
class SubtitleListView extends ConsumerStatefulWidget {
  const SubtitleListView({super.key, this.onImport, this.onAdd, this.onEdit});

  final VoidCallback? onImport;
  final VoidCallback? onAdd;
  final VoidCallback? onEdit;

  @override
  ConsumerState<SubtitleListView> createState() => _SubtitleListViewState();
}

class _SubtitleListViewState extends ConsumerState<SubtitleListView> {
  final ScrollController _controller = ScrollController();
  Timer? _resumeTimer;
  bool _userScrolling = false;
  int? _lastAutoScrollIndex;

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onUserScroll() {
    _userScrolling = true;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _userScrolling = false);
    });
    if (mounted) setState(() {});
  }

  /// 把第 [index] 句滚动到可视区中部。
  ///
  /// 用「比例 × 最大滚动距离」而不是依赖 item 高度：
  /// 字幕长短不一，高度不固定，比例法在高度不均时更稳，也不需要测量。
  void _autoScrollTo(int index, int total) {
    if (!_controller.hasClients || total <= 1) return;
    final position = _controller.position;
    final ratio = index / (total - 1);
    final target =
        (ratio * position.maxScrollExtent - position.viewportDimension * 0.32)
            .clamp(0.0, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 24) return;
    _controller.animateTo(
      target,
      duration: AppDimens.animSlow,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final subtitleState = ref.watch(subtitleProvider);
    final playback = ref.watch(playbackProvider);
    final settings = ref.watch(settingsProvider);
    SubtitleTrack? autoSentenceTrack;
    for (final track in subtitleState.activeTracks) {
      if (track.source == SubtitleSource.ai && track.name == 'AI 自动分句') {
        autoSentenceTrack = track;
        break;
      }
    }
    final focusMode = autoSentenceTrack != null;
    final lines = focusMode
        ? subtitleState.lines
              .where((line) => line.trackId == autoSentenceTrack!.id)
              .toList(growable: false)
        : subtitleState.lines;

    if (lines.isEmpty) {
      return _EmptySubtitle(
        loading: subtitleState.loading,
        onImport: widget.onImport,
        onAdd: widget.onAdd,
      );
    }

    // 当前播放位置落在哪句上（可能有双语两句同时命中）
    final currentIndexes = <int>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (playback.positionMs >= line.startMs &&
          playback.positionMs < line.endMs) {
        currentIndexes.add(i);
      }
    }
    final anchorIndex = currentIndexes.isEmpty ? -1 : currentIndexes.first;
    final sentencePlaylist = focusMode
        ? lines.map(_toCue).toList(growable: false)
        : const <SubtitleCue>[];

    // 当前句变化才滚动，避免每 80ms 一次的位置回调都在动列表
    if (_consumeAnchorChange(anchorIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _userScrolling) return;
        _autoScrollTo(anchorIndex, lines.length);
      });
    }

    return Column(
      children: [
        if (subtitleState.busyLabel != null) ...[
          LinearProgressIndicator(
            value: subtitleState.busyProgress,
            minHeight: 2,
            color: palette.accent,
            backgroundColor: palette.divider,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              subtitleState.busyLabel!,
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Row(
            children: [
              Icon(
                focusMode ? Icons.headphones_rounded : Icons.subtitles_rounded,
                size: 15,
                color: palette.accent,
              ),
              const SizedBox(width: 6),
              Text(
                '${focusMode ? '精听' : '字幕'} ${lines.length} 句'
                '${!focusMode && subtitleState.activeTracks.length > 1 ? ' · 双语' : ''}',
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
              const Spacer(),
              if (focusMode) ...[
                Text(
                  settings.autoAdvanceSentences
                      ? '自动推进 · ${settings.loopCount} 遍'
                      : '单句循环',
                  style: TextStyle(fontSize: 10.5, color: palette.textTertiary),
                ),
                Transform.scale(
                  scale: 0.78,
                  child: Switch.adaptive(
                    value: settings.autoAdvanceSentences,
                    onChanged: ref
                        .read(settingsProvider.notifier)
                        .setAutoAdvanceSentences,
                  ),
                ),
              ],
              if (_userScrolling)
                Text(
                  '已暂停自动滚动',
                  style: TextStyle(fontSize: 11, color: palette.textTertiary),
                ),
              const SizedBox(width: 4),
              if (widget.onEdit != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onEdit,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.edit_note_rounded,
                      size: 20,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _onUserScroll();
              }
              return false;
            },
            child: ListView.separated(
              controller: _controller,
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 16),
              itemCount: lines.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final line = lines[index];
                final isCurrent = currentIndexes.contains(index);
                final isLooped =
                    playback.loopRegion != null &&
                    playback.loopRegion!.startMs == line.startMs &&
                    playback.loopRegion!.endMs == line.endMs;
                return _SubtitleTile(
                  line: line,
                  displayIndex: index + 1,
                  focusMode: focusMode,
                  isCurrent: isCurrent,
                  isLooped: isLooped,
                  onTap: () {
                    if (focusMode) {
                      ref
                          .read(playbackProvider.notifier)
                          .loopSentence(
                            _toCue(line),
                            playlist: sentencePlaylist,
                            autoAdvance: settings.autoAdvanceSentences,
                          );
                    } else {
                      ref
                          .read(playbackProvider.notifier)
                          .jumpToCue(_toCue(line));
                    }
                  },
                  onLongPress: () {
                    if (focusMode) {
                      ref
                          .read(playbackProvider.notifier)
                          .jumpToCue(_toCue(line));
                    } else {
                      ref.read(playbackProvider.notifier).loopCue(_toCue(line));
                    }
                  },
                  onLoop: () {
                    if (focusMode) {
                      ref
                          .read(playbackProvider.notifier)
                          .loopSentence(
                            _toCue(line),
                            playlist: sentencePlaylist,
                            autoAdvance: settings.autoAdvanceSentences,
                          );
                    } else {
                      ref.read(playbackProvider.notifier).loopCue(_toCue(line));
                    }
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 当前句索引是否发生变化（变化才需要滚动）。
  bool _consumeAnchorChange(int index) {
    if (index < 0) return false;
    if (_lastAutoScrollIndex == index) return false;
    _lastAutoScrollIndex = index;
    return true;
  }

  SubtitleCue _toCue(SubtitleLine line) => SubtitleCue(
    index: line.lineIndex + 1,
    startMs: line.startMs,
    endMs: line.endMs,
    text: line.text,
  );
}

class _SubtitleTile extends StatelessWidget {
  const _SubtitleTile({
    required this.line,
    required this.displayIndex,
    required this.focusMode,
    required this.isCurrent,
    required this.isLooped,
    required this.onTap,
    required this.onLongPress,
    required this.onLoop,
  });

  final SubtitleLine line;
  final int displayIndex;
  final bool focusMode;
  final bool isCurrent;
  final bool isLooped;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onLoop;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return AnimatedContainer(
      duration: AppDimens.animFast,
      decoration: BoxDecoration(
        color: isCurrent
            ? palette.accent.withValues(alpha: 0.15)
            : palette.glass,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        border: Border.all(
          color: isCurrent
              ? palette.accent.withValues(alpha: 0.6)
              : palette.glassBorder,
          width: isCurrent ? 1.4 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (focusMode)
                  SizedBox(
                    width: 38,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$displayIndex',
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                            color: isCurrent
                                ? palette.accent
                                : palette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${(line.durationMs / 1000).toStringAsFixed(1)}s',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: palette.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: 42,
                    child: Text(
                      DurationUtils.formatShort(line.startMs),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isCurrent
                            ? palette.accent
                            : palette.textTertiary,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    line.text.isEmpty ? '（空字幕，点右上角编辑）' : line.text,
                    style: TextStyle(
                      fontSize: 14,
                      height: focusMode ? 1.3 : 1.35,
                      color: line.text.isEmpty
                          ? palette.textTertiary
                          : (isCurrent
                                ? palette.textPrimary
                                : palette.textPrimary),
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: focusMode ? 2 : null,
                    overflow: focusMode ? TextOverflow.ellipsis : null,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onLoop,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      isLooped ? Icons.repeat_on_rounded : Icons.repeat_rounded,
                      size: 18,
                      color: isLooped ? palette.accent : palette.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySubtitle extends StatelessWidget {
  const _EmptySubtitle({required this.loading, this.onImport, this.onAdd});

  final bool loading;
  final VoidCallback? onImport;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.subtitles_off_rounded,
            size: 34,
            color: palette.textTertiary,
          ),
          const SizedBox(height: 8),
          Text(
            '还没有字幕',
            style: TextStyle(fontSize: 13.5, color: palette.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            '导入 srt / ass / vtt，或从当前播放位置手动加一句',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: palette.textTertiary),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('导入字幕'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('添加字幕'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
