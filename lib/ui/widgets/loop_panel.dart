import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/duration_utils.dart';
import '../../data/models/loop_preset.dart';
import '../../data/models/media_item.dart' show LoopMode;
import '../../domain/playback/playback_state.dart';
import '../../providers/loop_preset_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/subtitle_provider.dart';
import 'glass.dart';

/// 「更多」面板：所有不常用的操作集中在这里。
///
/// 本次改版把原来铺在主界面的七个按钮收进这个面板，主界面只留
/// 播放控制与「循环 / 倍速 / 更多」三样。功能一个没少，只是不再挡路。
///
/// 面板内容分五组，顺序就是实际操作顺序：
/// 1. 选区（设 A / 设 B / 清除）
/// 2. 端点精调（0.1 秒级）
/// 3. 循环遍数（无限 / 指定遍数）
/// 4. 跟读停顿与录音对比
/// 5. 片段收藏
class LoopControlPanel extends ConsumerWidget {
  const LoopControlPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final snapshot = ref.watch(playbackProvider);
    final settings = ref.watch(settingsProvider);
    final presets = ref.watch(loopPresetProvider);
    final region = snapshot.loopRegion;
    final hasSubtitles = ref.watch(subtitleProvider).cues.isNotEmpty;

    // 标记点落位时同样走字幕吸附（需求 §4.1：手动选择的边界自动吸附）
    int snap(int ms) => ref
        .read(subtitleProvider.notifier)
        .snap(ms, enabled: settings.snapToSubtitle);

    return GlassPanel(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: palette.accent),
              const SizedBox(width: 8),
              const Text(
                '片段与跟读设置',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (region != null)
                Text(
                  '时长 ${DurationUtils.formatClock(region.endMs - region.startMs)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: palette.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // ---------------- 1. 选区 ----------------
          GlassSectionTitle(icon: Icons.content_cut_rounded, title: '选区'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GlassIconButton(
                  icon: Icons.first_page_rounded,
                  label: '设 A 为当前',
                  onTap: () {
                    final pos = snap(snapshot.positionMs);
                    final end =
                        region?.endMs ??
                        (pos + 3000).clamp(0, snapshot.durationMs);
                    final safeEnd = end > pos + 100 ? end : pos + 3000;
                    ref
                        .read(playbackProvider.notifier)
                        .setLoopRegion(pos, safeEnd);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassIconButton(
                  icon: Icons.last_page_rounded,
                  label: '设 B 为当前',
                  onTap: () {
                    final pos = snap(snapshot.positionMs);
                    final start =
                        region?.startMs ??
                        (pos - 3000).clamp(0, snapshot.durationMs);
                    final safeStart = start < pos - 100 ? start : 0;
                    ref
                        .read(playbackProvider.notifier)
                        .setLoopRegion(safeStart, pos);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassIconButton(
                  icon: Icons.layers_clear_rounded,
                  label: '清除选区',
                  onTap: region == null
                      ? null
                      : () => ref
                            .read(playbackProvider.notifier)
                            .clearLoopRegion(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasSubtitles
                ? '在时间轴上方那条轨道上左右拖动即可框选，两端会自动吸附到字幕句边界'
                : '在时间轴上方那条轨道上左右拖动即可框选片段',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: palette.textTertiary,
            ),
          ),
          if (region != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final message = await ref
                    .read(subtitleProvider.notifier)
                    .addSelectedSentence(region.startMs, region.endMs);
                final error = ref.read(subtitleProvider).error;
                messenger.showSnackBar(
                  SnackBar(content: Text(message ?? error ?? '保存失败')),
                );
              },
              icon: const Icon(Icons.playlist_add_rounded),
              label: const Text('将选区保存为一句'),
            ),
          ],

          // ---------------- 2. 端点精调 ----------------
          if (region != null) ...[
            const SizedBox(height: 16),
            GlassSectionTitle(
              icon: Icons.straighten_rounded,
              title: '端点精调（每次 0.1 秒）',
            ),
            const SizedBox(height: 8),
            _EndpointNudge(
              label: 'A',
              valueMs: region.startMs,
              onDelta: (delta) =>
                  ref.read(playbackProvider.notifier).nudgeLoopStart(delta),
            ),
            const SizedBox(height: 6),
            _EndpointNudge(
              label: 'B',
              valueMs: region.endMs,
              onDelta: (delta) =>
                  ref.read(playbackProvider.notifier).nudgeLoopEnd(delta),
            ),
          ],

          // ---------------- 3. 循环遍数 ----------------
          const SizedBox(height: 16),
          GlassSectionTitle(icon: Icons.repeat_rounded, title: '循环遍数'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GlassChip(
                label: '无限循环',
                selected:
                    region != null && snapshot.loopMode == LoopMode.infinite,
                onTap: () => ref
                    .read(playbackProvider.notifier)
                    .setLoopMode(LoopMode.infinite),
              ),
              for (final count in AppConstants.loopCountPresets)
                GlassChip(
                  label: '$count 遍',
                  selected:
                      region != null &&
                      snapshot.loopMode == LoopMode.count &&
                      snapshot.loopCount == count,
                  onTap: () => ref
                      .read(playbackProvider.notifier)
                      .setLoopMode(LoopMode.count, count: count),
                ),
            ],
          ),
          if (region == null) ...[
            const SizedBox(height: 6),
            Text(
              '提示：先框出一段选区，循环才会生效',
              style: TextStyle(fontSize: 11.5, color: palette.danger),
            ),
          ],

          // ---------------- 4. 跟读 ----------------
          const SizedBox(height: 16),
          GlassSectionTitle(
            icon: Icons.hourglass_bottom_rounded,
            title: '跟读停顿',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final gap in AppConstants.gapPresets)
                GlassChip(
                  label: gap == 0 ? '关闭' : '$gap 秒',
                  selected: settings.gapSeconds == gap,
                  onTap: () =>
                      ref.read(playbackProvider.notifier).setGapSeconds(gap),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '每循环一遍先静默这几秒，留时间让你开口跟读。默认值可以在设置里改。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: palette.textTertiary,
            ),
          ),

          const SizedBox(height: 16),
          const _RecordingRow(),

          // ---------------- 5. 片段收藏 ----------------
          if (region != null) ...[
            const SizedBox(height: 16),
            _PresetRow(presets: presets, region: region),
          ],
        ],
      ),
    );
  }
}

/// A / B 端点精调：每次 ±0.1 秒，长按连续微调（需求 §3.1-3）。
class _EndpointNudge extends StatelessWidget {
  const _EndpointNudge({
    required this.label,
    required this.valueMs,
    required this.onDelta,
  });

  final String label;
  final int valueMs;
  final ValueChanged<double> onDelta;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    const step = AppConstants.nudgeStepSeconds;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          DurationUtils.formatClock(valueMs),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const Spacer(),
        _NudgeButton(icon: Icons.remove, onPressed: () => onDelta(-step)),
        const SizedBox(width: 8),
        _NudgeButton(icon: Icons.add, onPressed: () => onDelta(step)),
      ],
    );
  }
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      // 长按连续微调
      onLongPressStart: (_) => onPressed(),
      child: Container(
        width: 40,
        height: 34,
        decoration: BoxDecoration(
          color: palette.glass,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          border: Border.all(color: palette.glassBorder),
        ),
        child: Icon(icon, size: 17, color: palette.textPrimary),
      ),
    );
  }
}

/// 录音相关操作行。
class _RecordingRow extends ConsumerWidget {
  const _RecordingRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final settings = ref.watch(settingsProvider);
    final clip = ref.watch(recordedClipProvider).valueOrNull;
    final snapshot = ref.watch(playbackProvider);
    final region = snapshot.loopRegion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassSectionTitle(icon: Icons.mic_rounded, title: '录音对比'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: GlassIconButton(
                icon: settings.recordDuringGap
                    ? Icons.mic_rounded
                    : Icons.mic_off_rounded,
                label: '停顿自动录音',
                active: settings.recordDuringGap,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .setRecordDuringGap(!settings.recordDuringGap),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GlassIconButton(
                icon: Icons.compare_arrows_rounded,
                label: '对比播放',
                onTap: clip == null || region == null
                    ? null
                    : () async {
                        final message = await ref
                            .read(playbackProvider.notifier)
                            .compareWithRecording();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(message)));
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GlassIconButton(
                icon: Icons.delete_outline_rounded,
                label: '删除录音',
                onTap: clip == null
                    ? null
                    : () =>
                          ref.read(playbackProvider.notifier).deleteRecording(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          clip == null
              ? '还没有录音。开启「停顿自动录音」后，每遍停顿会录下你的跟读。'
              : '已保存 1 段录音 · ${DurationUtils.formatShort(clip.durationMs)}，'
                    '点「对比播放」先听原声再听自己',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: palette.textTertiary,
          ),
        ),
        if (settings.recordDuringGap && !settings.gapEnabled) ...[
          const SizedBox(height: 6),
          Text(
            '提示：需要先把「跟读停顿」设成 1 秒以上，停顿期间才会录音',
            style: TextStyle(fontSize: 11.5, color: palette.danger),
          ),
        ],
      ],
    );
  }
}

/// 片段收藏行：保存当前片段 / 一键载入 / 长按删除。
class _PresetRow extends ConsumerWidget {
  const _PresetRow({required this.presets, required this.region});

  final List<LoopPreset> presets;
  final LoopRegion region;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassSectionTitle(
          icon: Icons.bookmark_add_outlined,
          title: '片段收藏',
          trailing: Text(
            '${presets.length} 个',
            style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            GlassChip(
              label: '收藏当前片段',
              icon: Icons.add_rounded,
              onTap: () async {
                await ref
                    .read(loopPresetProvider.notifier)
                    .add(startMs: region.startMs, endMs: region.endMs);
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已收藏当前片段')));
              },
            ),
            for (final preset in presets)
              GestureDetector(
                onLongPress: () =>
                    ref.read(loopPresetProvider.notifier).remove(preset.id!),
                child: GlassChip(
                  label: preset.note,
                  icon: Icons.bookmark_border_rounded,
                  color: palette.success,
                  onTap: () => ref
                      .read(playbackProvider.notifier)
                      .setLoopRegion(preset.startMs, preset.endMs),
                ),
              ),
          ],
        ),
        if (presets.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '轻点载入片段，长按删除',
            style: TextStyle(fontSize: 11, color: palette.textTertiary),
          ),
        ],
      ],
    );
  }
}
