/// 时间码解析 + 字幕文本清洗的公共工具。
///
/// 三种字幕格式的时间码长得像但不一样，把它们收敛到这里，
/// 各解析器只负责切分结构，不再各写一份时间解析。
class SubtitleTextUtils {
  SubtitleTextUtils._();

  /// 解析时间码为毫秒，无法识别返回 null。
  ///
  /// 支持的写法：
  /// - `00:00:01,250`（srt）
  /// - `00:00:01.250`（vtt）
  /// - `0:00:01.25`（ass，时长为百分秒）
  /// - `00:01.250`（vtt 允许省略小时段）
  static int? parseTimeCode(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    // srt 用逗号做毫秒分隔符
    text = text.replaceAll(',', '.');

    // vtt 的时间码后面可能跟定位参数：00:00:01.000 align:start position:10%
    final spaceIndex = text.indexOf(RegExp(r'\s'));
    if (spaceIndex > 0) text = text.substring(0, spaceIndex);

    final parts = text.split(':');
    if (parts.length < 2 || parts.length > 3) return null;

    try {
      int hours = 0;
      int minutes = 0;
      double seconds = 0;
      if (parts.length == 3) {
        hours = int.parse(parts[0]);
        minutes = int.parse(parts[1]);
        seconds = double.parse(parts[2]);
      } else {
        minutes = int.parse(parts[0]);
        seconds = double.parse(parts[1]);
      }
      if (minutes < 0 || seconds < 0) return null;
      return ((hours * 3600 + minutes * 60 + seconds) * 1000).round();
    } catch (_) {
      return null;
    }
  }

  /// 统一换行符，三种格式都要先做这一步再切结构。
  static String normalizeNewlines(String content) =>
      content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  /// 去掉 BOM 与零宽字符，某些字幕文件头部带这些不可见字符会导致首行匹配失败。
  static String stripInvisible(String content) => content
      .replaceAll('\uFEFF', '')
      .replaceAll('\u200B', '')
      .replaceAll('\u200E', '')
      .replaceAll('\u200F', '');

  /// 清理 ass 的 `{\...}` 样式覆盖指令。
  static String stripAssTags(String raw) =>
      raw.replaceAll(RegExp(r'\{[^{}]*\}'), '');

  /// 把 ass / vtt 的内联换行标记转成真正的换行。
  static String normalizeInlineBreaks(String raw) => raw
      .replaceAll(RegExp(r'\\[Nn]'), '\n')
      .replaceAll(RegExp(r'\\h'), ' ');

  /// 清理多余空白：行首行尾去空格，连续空行压成单行。
  static String tidy(String raw) {
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.join('\n');
  }

  /// 去掉 vtt 的 `<v Roger>` / `<c.class>` / `<00:00:01.000>` 这类内联标签。
  static String stripVttInlineTags(String raw) =>
      raw.replaceAll(RegExp(r'<[^>]*>'), '');

  /// 是不是「纯数字序号」行（srt 的索引行）。
  static bool isIndexLine(String line) => RegExp(r'^\d+$').hasMatch(line.trim());
}
