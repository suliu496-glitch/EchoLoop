import 'package:echoloop/domain/subtitles/subtitle_cue.dart';
import 'package:echoloop/domain/subtitles/subtitle_snapper.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造三句话，句间有静默空隙
const _cues = [
  SubtitleCue(index: 1, startMs: 1000, endMs: 3000, text: 'A'),
  SubtitleCue(index: 2, startMs: 3500, endMs: 6000, text: 'B'),
  SubtitleCue(index: 3, startMs: 7000, endMs: 9500, text: 'C'),
];

void main() {
  group('AB 边界吸附（阈值 1 秒）', () {
    test('阈值内吸附到最近的句子起点', () {
      final result = SubtitleSnapper.snap(1250, _cues, thresholdMs: 1000);
      expect(result.snapped, isTrue);
      expect(result.valueMs, 1000);
      expect(result.sourceEdge, SubtitleEdge.start);
      expect(result.sourceCueIndex, 1);
    });

    test('阈值内吸附到最近的句子终点', () {
      final result = SubtitleSnapper.snap(3150, _cues, thresholdMs: 1000);
      expect(result.snapped, isTrue);
      expect(result.valueMs, 3000);
      expect(result.sourceEdge, SubtitleEdge.end);
    });

    test('超出阈值不吸附，原值返回', () {
      // 3200 离 3000 有 200ms、离 3500 有 300ms，阈值收到 100ms 就都不该吸
      final result = SubtitleSnapper.snap(3200, _cues, thresholdMs: 100);
      expect(result.snapped, isFalse);
      expect(result.valueMs, 3200);
    });

    test('默认阈值是 1 秒（对应需求 §4.1）', () {
      // 离边界 800ms，默认阈值下应该吸住
      expect(SubtitleSnapper.snapWithDefaultThreshold(3800, _cues).snapped, isTrue);
      // 离最近边界 1200ms，默认阈值下不吸
      expect(SubtitleSnapper.snapWithDefaultThreshold(4700, _cues).snapped, isFalse);
    });

    test('取更近的那一端', () {
      // 3100 离 3000（终点）比离 3500（下一句起点）更近
      final result = SubtitleSnapper.snap(3100, _cues, thresholdMs: 1000);
      expect(result.valueMs, 3000);

      // 3400 离 3500 更近
      final result2 = SubtitleSnapper.snap(3400, _cues, thresholdMs: 1000);
      expect(result2.valueMs, 3500);
    });

    test('没有字幕时不吸附', () {
      final result = SubtitleSnapper.snap(1234, const [], thresholdMs: 1000);
      expect(result.snapped, isFalse);
      expect(result.valueMs, 1234);
    });
  });

  group('当前句高亮定位', () {
    test('落在句子区间内', () {
      expect(SubtitleSnapper.cueAt(2000, _cues)?.text, 'A');
      expect(SubtitleSnapper.cueAt(5000, _cues)?.text, 'B');
    });

    test('句间空隙短暂保留高亮，超过保留时长返回 null', () {
      // 3000-3500 是空隙，保留 400ms 内还算 A
      expect(SubtitleSnapper.cueAt(3200, _cues)?.text, 'A');
      // 3400 已超过 3000 + 400
      expect(SubtitleSnapper.cueAt(3400, _cues), isNull);
    });

    test('早于第一句时无高亮', () {
      expect(SubtitleSnapper.cueAt(500, _cues), isNull);
    });

    test('超过最后一句的保留窗口后无高亮', () {
      expect(SubtitleSnapper.cueAt(9700, _cues)?.text, 'C');
      expect(SubtitleSnapper.cueAt(10500, _cues), isNull);
    });
  });
}
