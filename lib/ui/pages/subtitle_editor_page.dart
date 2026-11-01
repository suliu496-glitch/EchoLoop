import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/duration_utils.dart';
import '../../data/models/subtitle_models.dart';
import '../../domain/subtitles/subtitle_text_utils.dart';
import '../../providers/playback_provider.dart';
import '../../providers/subtitle_provider.dart';
import '../adaptive/screen_adaptation.dart';
import '../widgets/glass.dart';
import '../widgets/media_card.dart' show glassInputDecoration;
import '../widgets/swipe_sentence_tile.dart';

/// 字幕编辑页（需求 §3.2-5）。
///
/// 与播放联动：进入编辑页自动暂停；点某句会跳转到该句起点试听；
/// 单句起止时间可以精确到毫秒手动改。
class SubtitleEditorPage extends ConsumerStatefulWidget {
  const SubtitleEditorPage({super.key, required this.mediaId});

  final int mediaId;

  @override
  ConsumerState<SubtitleEditorPage> createState() => _SubtitleEditorPageState();
}

class _SubtitleEditorPageState extends ConsumerState<SubtitleEditorPage> {
  int? _trackId;

  @override
  void initState() {
    super.initState();
    // 编辑时视频暂停（需求 §3.2-5）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(playbackProvider.notifier).pause();
      await ref.read(subtitleProvider.notifier).loadFor(widget.mediaId);
      _selectDefaultTrack();
    });
  }

  void _selectDefaultTrack() {
    final tracks = ref.read(subtitleProvider).tracks;
    if (tracks.isEmpty) {
      setState(() => _trackId = null);
      return;
    }
    final first = tracks.firstWhere(
      (track) => track.isActive,
      orElse: () => tracks.first,
    );
    setState(() => _trackId = first.id);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final state = ref.watch(subtitleProvider);
    final tracks = state.tracks;
    final trackId = _trackId ?? (tracks.isEmpty ? null : tracks.first.id);
    final lines = state.lines.where((line) => line.trackId == trackId).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('字幕编辑'),
        actions: [
          IconButton(
            tooltip: '导入字幕文件',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: () async {
              final message = await ref
                  .read(subtitleProvider.notifier)
                  .importFromPicker();
              if (!mounted || message == null) return;
              _toast(message);
              _selectDefaultTrack();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'new') {
                final message = await ref
                    .read(subtitleProvider.notifier)
                    .createManualTrackAndLine(
                      ref.read(playbackProvider).positionMs,
                    );
                if (!mounted) return;
                _toast(message ?? '已新建字幕轨');
                _selectDefaultTrack();
                return;
              }
              if (value == 'clear' && trackId != null) {
                if (!await _confirmTrackRemoval('清空当前轨的所有句子？') || !mounted) {
                  return;
                }
                await ref.read(subtitleProvider.notifier).clearTrack(trackId);
                if (!mounted) return;
                _toast('已清空这条字幕轨');
                return;
              }
              if (value == 'delete' && trackId != null) {
                if (!await _confirmTrackRemoval('删除当前字幕轨及其所有句子？') || !mounted) {
                  return;
                }
                await ref.read(subtitleProvider.notifier).deleteTrack(trackId);
                if (!mounted) return;
                _toast('已删除这条字幕轨');
                _selectDefaultTrack();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'new', child: Text('新建手写字幕轨')),
              const PopupMenuItem(value: 'clear', child: Text('清空当前轨')),
              const PopupMenuItem(value: 'delete', child: Text('删除当前轨')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final message = await ref
              .read(subtitleProvider.notifier)
              .addLineAt(ref.read(playbackProvider).positionMs);
          if (!mounted) return;
          _toast(message ?? '已插入一句');
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('在当前时间插入'),
      ),
      body: SafeArea(
        child: ConstrainedContent(
          child: Column(
            children: [
              if (tracks.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      '还没有字幕轨，先导入字幕文件或新建一条手写轨',
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                )
              else ...[
                _buildTrackSelector(tracks, trackId),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.pagePadding,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '共 ${lines.length} 句 · 点击试听，右侧图标编辑',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.textTertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: lines.isEmpty
                      ? Center(
                          child: Text(
                            '这条轨还没有字幕句，点右下角插入一句',
                            style: TextStyle(
                              fontSize: 13,
                              color: palette.textSecondary,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            AppDimens.pagePadding,
                            4,
                            AppDimens.pagePadding,
                            120,
                          ),
                          itemCount: lines.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) =>
                              _buildLineTile(lines[index], index + 1, trackId!),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackSelector(List<SubtitleTrack> tracks, int? trackId) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final track = tracks[index];
          return GlassChip(
            label: '${track.name}（${track.source.label}）',
            selected: track.id == trackId,
            onTap: () => setState(() => _trackId = track.id),
          );
        },
      ),
    );
  }

  Widget _buildLineTile(SubtitleLine line, int displayIndex, int trackId) {
    final palette = context.palette;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      radius: AppDimens.radiusMd,
      onTap: () {
        // 点一句 → 跳到起点试听
        ref.read(playbackProvider.notifier).seekTo(line.startMs);
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$displayIndex',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.accent,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${DurationUtils.formatMilliseconds(line.startMs)} → '
                  '${DurationUtils.formatMilliseconds(line.endMs)}',
                  style: TextStyle(fontSize: 11, color: palette.textTertiary),
                ),
                const SizedBox(height: 4),
                Text(
                  line.text.isEmpty ? '（空）' : line.text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: line.text.isEmpty
                        ? palette.textTertiary
                        : palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            iconSize: 18,
            tooltip: '编辑这一句',
            onPressed: () => _openLineEditor(line, trackId),
            icon: Icon(Icons.edit_outlined, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 单句编辑
  // ------------------------------------------------------------------

  Future<void> _openLineEditor(SubtitleLine line, int trackId) async {
    await ref.read(playbackProvider.notifier).pause();

    final textController = TextEditingController(text: line.text);
    final startController = TextEditingController(
      text: DurationUtils.formatMilliseconds(line.startMs),
    );
    final endController = TextEditingController(
      text: DurationUtils.formatMilliseconds(line.endMs),
    );
    String? errorText;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // 横屏矮屏上不加高度约束的话，面板会顶到屏幕顶端，按钮点不到
      constraints: ScreenAdaptation.sheetConstraints(context),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final palette = sheetContext.palette;

          Future<void> save() async {
            final start = SubtitleTextUtils.parseTimeCode(startController.text);
            final end = SubtitleTextUtils.parseTimeCode(endController.text);
            if (start == null || end == null) {
              setSheetState(() => errorText = '时间格式应为 00:00:01.250');
              return;
            }
            if (end <= start) {
              setSheetState(() => errorText = '结束时间必须晚于开始时间');
              return;
            }
            final ok = await ref
                .read(subtitleProvider.notifier)
                .updateLine(
                  line.copyWith(
                    startMs: start,
                    endMs: end,
                    text: textController.text,
                    source: SubtitleSource.manual,
                  ),
                );
            if (!sheetContext.mounted) return;
            if (ok) {
              if (ref.read(playbackProvider).mediaId == line.mediaId) {
                await ref
                    .read(playbackProvider.notifier)
                    .sentenceChanged(startMs: line.startMs, endMs: line.endMs);
              }
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            } else {
              setSheetState(
                () => errorText = ref.read(subtitleProvider).error ?? '保存失败',
              );
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: GlassPanel(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const GlassSectionTitle(
                    icon: Icons.edit_note_rounded,
                    title: '编辑这一句',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(fontSize: 15, height: 1.35),
                    decoration: glassInputDecoration(
                      sheetContext,
                      hintText: '字幕文本',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _TimeField(
                          label: '开始（毫秒级）',
                          controller: startController,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TimeField(
                          label: '结束（毫秒级）',
                          controller: endController,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '微调',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _MiniButton(
                        label: '起点 -0.1s',
                        onTap: () => _nudge(startController, -0.1),
                      ),
                      const SizedBox(width: 6),
                      _MiniButton(
                        label: '起点 +0.1s',
                        onTap: () => _nudge(startController, 0.1),
                      ),
                      const SizedBox(width: 10),
                      _MiniButton(
                        label: '终点 -0.1s',
                        onTap: () => _nudge(endController, -0.1),
                      ),
                      const SizedBox(width: 6),
                      _MiniButton(
                        label: '终点 +0.1s',
                        onTap: () => _nudge(endController, 0.1),
                      ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: TextStyle(fontSize: 12, color: palette.danger),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          final confirmed = await confirmDeleteSentence(
                            sheetContext,
                            line.lineIndex + 1,
                          );
                          if (!confirmed || !sheetContext.mounted) return;
                          final deleted = await ref
                              .read(subtitleProvider.notifier)
                              .deleteLine(line.id!);
                          if (!sheetContext.mounted) return;
                          if (deleted) {
                            if (ref.read(playbackProvider).mediaId ==
                                line.mediaId) {
                              await ref
                                  .read(playbackProvider.notifier)
                                  .sentenceChanged(
                                    startMs: line.startMs,
                                    endMs: line.endMs,
                                  );
                            }
                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                          }
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('删除'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: save, child: const Text('保存')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    textController.dispose();
    startController.dispose();
    endController.dispose();
  }

  void _nudge(TextEditingController controller, double deltaSeconds) {
    final current = SubtitleTextUtils.parseTimeCode(controller.text);
    if (current == null) return;
    final next = current + (deltaSeconds * 1000).round();
    controller.text = DurationUtils.formatMilliseconds(next < 0 ? 0 : next);
  }

  Future<bool> _confirmTrackRemoval(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认删除'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      style: const TextStyle(fontSize: 13.5),
      decoration: glassInputDecoration(context, labelText: label),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: palette.glass,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.glassBorder),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: palette.textPrimary),
        ),
      ),
    );
  }
}
