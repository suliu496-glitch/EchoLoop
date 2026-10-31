import '../../core/constants/app_constants.dart';
import 'subtitle_cue.dart';

/// 吸附结果。
class SnapResult {
  const SnapResult({
    required this.valueMs,
    required this.snapped,
    this.sourceCueIndex,
    this.sourceEdge,
  });

  /// 吸附后的时间点（未吸附时等于入参）
  final int valueMs;

  /// 是否真的发生了吸附
  final bool snapped;

  /// 吸附到的是第几句
  final int? sourceCueIndex;

  /// 吸附到该句的哪一端
  final SubtitleEdge? sourceEdge;

  @override
  String toString() =>
      snapped ? '吸附到 #$sourceCueIndex 的${sourceEdge?.label}' : '未吸附';
}

enum SubtitleEdge {
  start('起点'),
  end('终点');

  const SubtitleEdge(this.label);

  final String label;
}

/// AB 片段边界吸附算法（需求 §4.1）。
///
/// 目标：手动拖 A/B 点时，如果离某句字幕的起止时间很近，
/// 就自动贴上去，避免把一句话从中间切开。
///
/// 两条约束：
/// - 阈值默认 1 秒，超出范围不动；
/// - 只在「拖动」这种粗粒度操作上生效，±0.1 秒的精调按钮不调用它，
///   这样用户吸附后还能手动脱离（需求原文：吸附后仍可手动微调脱离吸附）。
class SubtitleSnapper {
  SubtitleSnapper._();

  static SnapResult snap(
    int valueMs,
    List<SubtitleCue> cues, {
    int thresholdMs = 1000,
  }) {
    if (cues.isEmpty || thresholdMs <= 0) {
      return SnapResult(valueMs: valueMs, snapped: false);
    }

    var bestDistance = thresholdMs + 1;
    int? bestValue;
    int? bestCueIndex;
    SubtitleEdge? bestEdge;

    for (final cue in cues) {
      // 起点
      final startDistance = (cue.startMs - valueMs).abs();
      if (startDistance <= thresholdMs && startDistance < bestDistance) {
        bestDistance = startDistance;
        bestValue = cue.startMs;
        bestCueIndex = cue.index;
        bestEdge = SubtitleEdge.start;
      }
      // 终点
      final endDistance = (cue.endMs - valueMs).abs();
      if (endDistance <= thresholdMs && endDistance < bestDistance) {
        bestDistance = endDistance;
        bestValue = cue.endMs;
        bestCueIndex = cue.index;
        bestEdge = SubtitleEdge.end;
      }
    }

    if (bestValue == null) {
      return SnapResult(valueMs: valueMs, snapped: false);
    }
    return SnapResult(
      valueMs: bestValue,
      snapped: true,
      sourceCueIndex: bestCueIndex,
      sourceEdge: bestEdge,
    );
  }

  /// 便捷方法：把秒级阈值换算成毫秒后调用 [snap]。
  static SnapResult snapWithDefaultThreshold(int valueMs, List<SubtitleCue> cues) =>
      snap(
        valueMs,
        cues,
        thresholdMs:
            (AppConstants.snapThresholdSeconds * 1000).round(),
      );

  /// 找出某个时间点落在哪一句里（用于播放时高亮当前句）。
  ///
  /// cues 必须按 startMs 升序（`SubtitleDao.activeLinesOf` 已保证）。
  /// [holdMs] 是句间空隙的保留时长：两句之间有静默时，高亮不立刻消失，
  /// 视觉上更连续，不会一闪一闪。
  static SubtitleCue? cueAt(
    int positionMs,
    List<SubtitleCue> cues, {
    int holdMs = 400,
  }) {
    if (cues.isEmpty) return null;

    // 二分找到最后一个 startMs <= positionMs 的句子
    var low = 0;
    var high = cues.length - 1;
    var found = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (cues[mid].startMs <= positionMs) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (found < 0) return null;

    final cue = cues[found];
    if (positionMs < cue.endMs) return cue;
    return positionMs - cue.endMs < holdMs ? cue : null;
  }
}
