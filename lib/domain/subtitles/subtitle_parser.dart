import '../../core/errors/app_exception.dart';
import 'subtitle_cue.dart';
import 'subtitle_text_utils.dart';

/// 字幕解析器接口。
///
/// 需求 §5 明确「不引入重型第三方库，自行解析保证可控」，
/// 三种格式各自实现一个子类，统一输出 [SubtitleCue] 列表。
/// 未来要加 stl / ttml 之类，只要新增实现并注册进 [SubtitleParserRegistry]。
abstract class SubtitleParser {
  /// 格式名，用于提示文案
  String get formatName;

  /// 负责的扩展名（小写，不带点）
  List<String> get extensions;

  /// 解析正文。失败时抛 [SubtitleException]，由调用方转成可读提示。
  List<SubtitleCue> parse(String content);

  /// 解析后的通用收尾：按时间排序 + 重排显示序号 + 丢弃长度为负的脏数据。
  List<SubtitleCue> finalize(List<SubtitleCue> cues) {
    final cleaned = cues
        .where((cue) => cue.endMs > cue.startMs && cue.text.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    return [
      for (var i = 0; i < cleaned.length; i++)
        cleaned[i].copyWith(index: i + 1, text: SubtitleTextUtils.tidy(cleaned[i].text)),
    ];
  }
}

/// 解析器注册表：按扩展名分发。
class SubtitleParserRegistry {
  SubtitleParserRegistry._();

  static final List<SubtitleParser> _parsers = [
    SrtSubtitleParser(),
    VttSubtitleParser(),
    AssSubtitleParser(),
  ];

  static List<String> get supportedExtensions =>
      [for (final parser in _parsers) ...parser.extensions];

  static SubtitleParser? forExtension(String extension) {
    final normalized = extension.toLowerCase();
    for (final parser in _parsers) {
      if (parser.extensions.contains(normalized)) return parser;
    }
    return null;
  }

  /// 按扩展名解析。不支持的扩展名抛 [SubtitleException]。
  static List<SubtitleCue> parse(String content, String extension) {
    final parser = forExtension(extension);
    if (parser == null) {
      throw SubtitleException(
        '暂不支持 .$extension 格式的字幕',
        detail: '当前支持：${supportedExtensions.map((e) => '.$e').join('、')}',
        code: 'unsupported_format',
      );
    }
    final cues = parser.parse(content);
    if (cues.isEmpty) {
      throw SubtitleException(
        '字幕内容解析为空',
        detail: '文件可能不是 .$extension 格式，或者内容被加密/截断',
        code: 'empty_result',
      );
    }
    return cues;
  }
}

// ---------------------------------------------------------------------------
// SRT：块结构，`序号 / 时间行 / 文本行*`，块之间空行分隔
// ---------------------------------------------------------------------------
class SrtSubtitleParser extends SubtitleParser {
  @override
  String get formatName => 'SRT';

  @override
  List<String> get extensions => const ['srt'];

  @override
  List<SubtitleCue> parse(String content) {
    final normalized = SubtitleTextUtils.stripInvisible(
      SubtitleTextUtils.normalizeNewlines(content),
    );
    if (normalized.trim().isEmpty) {
      throw const SubtitleException('字幕文件是空的', code: 'empty_file');
    }

    final cues = <SubtitleCue>[];
    final blocks = normalized.split(RegExp(r'\n{2,}'));
    for (final block in blocks) {
      final lines = block.split('\n');
      final arrowIndex = lines.indexWhere((line) => line.contains('-->'));
      if (arrowIndex < 0) continue;

      final range = _splitRange(lines[arrowIndex]);
      if (range == null) continue;

      // 时间行之后的所有非空行都是文本（srt 允许一句拆成多行）
      final textLines = lines
          .skip(arrowIndex + 1)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (textLines.isEmpty) continue;

      cues.add(
        SubtitleCue(
          index: cues.length + 1,
          startMs: range.$1,
          endMs: range.$2,
          text: textLines.join('\n'),
        ),
      );
    }
    return finalize(cues);
  }

  (int, int)? _splitRange(String line) {
    final parts = line.split('-->');
    if (parts.length < 2) return null;
    final start = SubtitleTextUtils.parseTimeCode(parts[0]);
    final end = SubtitleTextUtils.parseTimeCode(parts[1]);
    if (start == null || end == null) return null;
    return (start, end);
  }
}

// ---------------------------------------------------------------------------
// VTT：结构接近 srt，但带 WEBVTT 头，允许 cue id、NOTE 注释、内联标签
// ---------------------------------------------------------------------------
class VttSubtitleParser extends SubtitleParser {
  @override
  String get formatName => 'WebVTT';

  @override
  List<String> get extensions => const ['vtt'];

  @override
  List<SubtitleCue> parse(String content) {
    final normalized = SubtitleTextUtils.stripInvisible(
      SubtitleTextUtils.normalizeNewlines(content),
    );
    if (normalized.trim().isEmpty) {
      throw const SubtitleException('字幕文件是空的', code: 'empty_file');
    }

    final cues = <SubtitleCue>[];
    final blocks = normalized.split(RegExp(r'\n{2,}'));
    for (final block in blocks) {
      final lines = block.split('\n');
      // 跳过文件头与注释块
      if (lines.isNotEmpty) {
        final head = lines.first.trim().toUpperCase();
        if (head.startsWith('WEBVTT') || head.startsWith('NOTE') || head.startsWith('STYLE')) {
          continue;
        }
      }

      final arrowIndex = lines.indexWhere((line) => line.contains('-->'));
      if (arrowIndex < 0) continue;

      final range = _splitRange(lines[arrowIndex]);
      if (range == null) continue;

      final textLines = lines
          .skip(arrowIndex + 1)
          .map((line) => SubtitleTextUtils.stripVttInlineTags(line).trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (textLines.isEmpty) continue;

      cues.add(
        SubtitleCue(
          index: cues.length + 1,
          startMs: range.$1,
          endMs: range.$2,
          text: textLines.join('\n'),
        ),
      );
    }
    return finalize(cues);
  }

  (int, int)? _splitRange(String line) {
    final parts = line.split('-->');
    if (parts.length < 2) return null;
    final start = SubtitleTextUtils.parseTimeCode(parts[0]);
    final end = SubtitleTextUtils.parseTimeCode(parts[1]);
    if (start == null || end == null) return null;
    return (start, end);
  }
}

// ---------------------------------------------------------------------------
// ASS/SSA：`[Events]` 段里的 Dialogue 行，靠 Format 行确定列位置
// ---------------------------------------------------------------------------
class AssSubtitleParser extends SubtitleParser {
  @override
  String get formatName => 'ASS';

  @override
  List<String> get extensions => const ['ass', 'ssa'];

  /// 标准字段顺序，[Events] 段里的 Format 行会覆盖它
  static const List<String> _defaultFormat = [
    'layer',
    'start',
    'end',
    'style',
    'name',
    'marginl',
    'marginr',
    'marginv',
    'effect',
    'text',
  ];

  @override
  List<SubtitleCue> parse(String content) {
    final normalized = SubtitleTextUtils.stripInvisible(
      SubtitleTextUtils.normalizeNewlines(content),
    );
    if (normalized.trim().isEmpty) {
      throw const SubtitleException('字幕文件是空的', code: 'empty_file');
    }

    final lines = normalized.split('\n');
    var inEventsSection = false;
    var format = _defaultFormat;
    final cues = <SubtitleCue>[];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('[')) {
        inEventsSection = line.toLowerCase().startsWith('[events]');
        continue;
      }
      if (!inEventsSection) continue;

      final lower = line.toLowerCase();
      if (lower.startsWith('format:')) {
        format = line
            .substring(line.indexOf(':') + 1)
            .split(',')
            .map((field) => field.trim().toLowerCase())
            .toList();
        continue;
      }
      if (!lower.startsWith('dialogue:')) continue;

      final cue = _parseDialogue(line.substring(line.indexOf(':') + 1), format);
      if (cue != null) cues.add(cue);
    }

    return finalize(cues);
  }

  SubtitleCue? _parseDialogue(String payload, List<String> format) {
    final startIndex = format.indexOf('start');
    final endIndex = format.indexOf('end');
    final textIndex = format.indexOf('text');
    if (startIndex < 0 || endIndex < 0 || textIndex < 0) return null;

    // Text 列里本身可能含逗号，所以不能简单地整体 split(',')：
    // 逐列按逗号切分，最后一列（Text 按规范就是最后一列）吃掉剩余全部内容。
    final parts = <String>[];
    var rest = payload;
    for (var i = 0; i < format.length; i++) {
      if (i == format.length - 1) {
        parts.add(rest);
        break;
      }
      final comma = rest.indexOf(',');
      if (comma < 0) {
        parts.add(rest);
        rest = '';
        break;
      }
      parts.add(rest.substring(0, comma));
      rest = rest.substring(comma + 1);
    }
    if (parts.length <= textIndex) return null;

    final start = SubtitleTextUtils.parseTimeCode(parts[startIndex]);
    final end = SubtitleTextUtils.parseTimeCode(parts[endIndex]);
    if (start == null || end == null) return null;

    final text = SubtitleTextUtils.tidy(
      SubtitleTextUtils.normalizeInlineBreaks(
        SubtitleTextUtils.stripAssTags(parts[textIndex]),
      ),
    );
    if (text.isEmpty) return null;

    return SubtitleCue(index: 0, startMs: start, endMs: end, text: text);
  }
}
