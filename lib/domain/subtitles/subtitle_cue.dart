/// 解析完成的一句字幕。
///
/// 这是「域模型」：只关心时间与文本，不关心它存在哪张表、属于哪条轨。
/// 字幕解析器、吸附算法、循环引擎都只依赖它。
class SubtitleCue {
  const SubtitleCue({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  /// 显示序号，从 1 开始
  final int index;

  final int startMs;
  final int endMs;
  final String text;

  int get durationMs => endMs - startMs;

  bool containsMs(int ms) => ms >= startMs && ms < endMs;

  /// 单行摘要，用于调试与导出
  @override
  String toString() => '#$index [$startMs - $endMs] $text';

  SubtitleCue copyWith({int? index, int? startMs, int? endMs, String? text}) {
    return SubtitleCue(
      index: index ?? this.index,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      text: text ?? this.text,
    );
  }
}
