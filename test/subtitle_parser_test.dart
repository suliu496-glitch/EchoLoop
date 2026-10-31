import 'package:echoloop/core/errors/app_exception.dart';
import 'package:echoloop/domain/subtitles/subtitle_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SRT 解析', () {
    test('标准结构：序号 + 时间行 + 文本', () {
      const content = '''
1
00:00:01,000 --> 00:00:04,000
Hello there.

2
00:00:05,500 --> 00:00:08,250
How are you
doing today?
''';
      final cues = SubtitleParserRegistry.parse(content, 'srt');

      expect(cues.length, 2);
      expect(cues[0].index, 1);
      expect(cues[0].startMs, 1000);
      expect(cues[0].endMs, 4000);
      expect(cues[0].text, 'Hello there.');
      // 多行文本合并保留换行
      expect(cues[1].text, 'How are you\ndoing today?');
      expect(cues[1].startMs, 5500);
      expect(cues[1].endMs, 8250);
    });

    test('兼容缺序号、CRLF、BOM 的脏文件', () {
      const content =
          '\uFEFF00:00:02,000 --> 00:00:03,000\r\n第一句\r\n\r\n'
          '00:00:04,000 --> 00:00:05,000\r\n第二句\r\n';

      final cues = SubtitleParserRegistry.parse(content, 'srt');
      expect(cues.length, 2);
      expect(cues[0].text, '第一句');
      expect(cues[1].text, '第二句');
    });

    test('乱序输入会被按时间重排并重编序号', () {
      const content = '''
1
00:00:10,000 --> 00:00:11,000
后一句

2
00:00:01,000 --> 00:00:02,000
前一句
''';
      final cues = SubtitleParserRegistry.parse(content, 'srt');
      expect(cues.first.text, '前一句');
      expect(cues.first.index, 1);
      expect(cues.last.index, 2);
    });
  });

  group('VTT 解析', () {
    test('跳过 WEBVTT 头与 NOTE，清理内联标签', () {
      const content = '''
WEBVTT

NOTE 这是一条注释

00:00:01.000 --> 00:00:03.000 align:start position:10%
<v Roger>Hello <c.yellow>world</c>

00:00:04.000 --> 00:00:06.000
Second line
''';
      final cues = SubtitleParserRegistry.parse(content, 'vtt');
      expect(cues.length, 2);
      expect(cues[0].text, 'Hello world');
      expect(cues[0].startMs, 1000);
      expect(cues[1].text, 'Second line');
    });

    test('兼容省略小时段的时间码', () {
      const content = '''
WEBVTT

01:30.500 --> 01:32.000
短格式
''';
      final cues = SubtitleParserRegistry.parse(content, 'vtt');
      expect(cues.single.startMs, 90500);
    });
  });

  group('ASS 解析', () {
    test('按 Format 列定位，Text 里的逗号不被切碎', () {
      const content = '''
[Script Info]
Title: demo

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,{\\i1}Hello, world{\\i0}
Dialogue: 0,0:00:04.00,0:00:06.00,Default,,0,0,0,,第一行\\N第二行
''';
      final cues = SubtitleParserRegistry.parse(content, 'ass');

      expect(cues.length, 2);
      expect(cues[0].text, 'Hello, world');
      expect(cues[0].startMs, 1000);
      expect(cues[0].endMs, 3500);
      // \N 转成换行
      expect(cues[1].text, '第一行\n第二行');
    });
  });

  group('异常与边界', () {
    test('不支持的扩展名抛 SubtitleException', () {
      expect(
        () => SubtitleParserRegistry.parse('whatever', 'stl'),
        throwsA(isA<SubtitleException>()),
      );
    });

    test('内容为空抛异常', () {
      expect(
        () => SubtitleParserRegistry.parse('   \n  ', 'srt'),
        throwsA(isA<SubtitleException>()),
      );
    });

    test('结束时间早于开始时间的脏数据被丢弃', () {
      const content = '''
1
00:00:05,000 --> 00:00:01,000
坏数据

2
00:00:06,000 --> 00:00:07,000
好数据
''';
      final cues = SubtitleParserRegistry.parse(content, 'srt');
      expect(cues.length, 1);
      expect(cues.single.text, '好数据');
    });
  });
}
