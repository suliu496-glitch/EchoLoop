import 'package:echoloop/core/utils/duration_utils.dart';
import 'package:echoloop/data/models/media_item.dart' show LoopMode;
import 'package:echoloop/domain/playback/loop_math.dart';
import 'package:echoloop/domain/playback/playback_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('时间格式化', () {
    test('播放时钟精确到 0.1 秒', () {
      expect(DurationUtils.formatClock(0), '00:00.0');
      expect(DurationUtils.formatClock(1234), '00:01.2');
      expect(DurationUtils.formatClock(65000), '01:05.0');
      expect(DurationUtils.formatClock(3661500), '01:01:01.5');
    });

    test('列表时长不带小数', () {
      expect(DurationUtils.formatShort(0), '00:00');
      expect(DurationUtils.formatShort(75400), '01:15');
      expect(DurationUtils.formatShort(3723000), '1:02:03');
    });

    test('毫秒级时间戳用于字幕编辑', () {
      expect(DurationUtils.formatMilliseconds(1250), '00:00:01.250');
      expect(DurationUtils.formatMilliseconds(3661000), '01:01:01.000');
    });
  });

  group('倍速换算', () {
    test('半速播 3 秒音频需要 6 秒真实时间', () {
      expect(DurationUtils.realDurationMs(3000, 0.5), 6000);
    });

    test('2 倍速播 3 秒音频需要 1.5 秒真实时间', () {
      expect(DurationUtils.realDurationMs(3000, 2.0), 1500);
    });

    test('倍速非法时不做换算', () {
      expect(DurationUtils.realDurationMs(3000, 0), 3000);
    });
  });

  group('循环边界计算', () {
    const region = LoopRegion(startMs: 1000, endMs: 4000);

    test('区间外返回 null（不武装循环）', () {
      expect(
        LoopMath.msUntilBoundary(positionMs: 500, region: region, speed: 1),
        isNull,
      );
      expect(
        LoopMath.msUntilBoundary(positionMs: 4500, region: region, speed: 1),
        isNull,
      );
    });

    test('区间内给出剩余真实时长（含容差）', () {
      // 4000 + 30 - 2000 = 2030
      expect(
        LoopMath.msUntilBoundary(positionMs: 2000, region: region, speed: 1),
        2030,
      );
      // 0.5 倍速翻倍
      expect(
        LoopMath.msUntilBoundary(positionMs: 2000, region: region, speed: 0.5),
        4060,
      );
    });

    test('已越过边界时返回 null（越过之后由轮询 shouldTrigger 收口）', () {
      expect(
        LoopMath.msUntilBoundary(positionMs: 4100, region: region, speed: 1),
        isNull,
      );
      expect(LoopMath.shouldTrigger(positionMs: 4100, region: region), isTrue);
    });

    test('贴着 B 点时剩余时间只剩容差那一小截', () {
      expect(
        LoopMath.msUntilBoundary(positionMs: 3999, region: region, speed: 1),
        31,
      );
    });

    test('轮询触发判定与「是否需要归位」判定', () {
      expect(LoopMath.shouldTrigger(positionMs: 4029, region: region), isFalse);
      expect(LoopMath.shouldTrigger(positionMs: 4030, region: region), isTrue);
      // 播到 B 点之后：改成更短的片段时必须马上回到 A，否则用户觉得「改了没用」
      expect(
        LoopMath.shouldRewindToStart(positionMs: 4200, region: region),
        isTrue,
      );
      // 把 A 往后挪，当前位置落到新 A 之前，同样要归位
      expect(
        LoopMath.shouldRewindToStart(positionMs: 800, region: region),
        isTrue,
      );
      // 位置就在区间内：不用动，继续播
      expect(
        LoopMath.shouldRewindToStart(positionMs: 2000, region: region),
        isFalse,
      );
    });

    test('跳到 B 点之后，旧选区应暂时失效', () {
      expect(
        LoopMath.shouldSuppressLoop(positionMs: 4200, region: region),
        isTrue,
      );
      expect(
        LoopMath.shouldSuppressLoop(positionMs: 2000, region: region),
        isFalse,
      );
    });
  });

  group('循环模式行为', () {
    test('无限循环永远继续', () {
      expect(
        LoopMath.actionAfterBoundary(mode: LoopMode.infinite, remaining: null),
        BoundaryAction.nextPass,
      );
      expect(
        LoopMath.remainingAfterBoundary(mode: LoopMode.infinite, remaining: null),
        isNull,
      );
    });

    test('指定 3 遍：前两次继续，第三次停下', () {
      // 第一遍结束，还剩 2 遍
      expect(
        LoopMath.actionAfterBoundary(mode: LoopMode.count, remaining: 3),
        BoundaryAction.countDown,
      );
      expect(
        LoopMath.remainingAfterBoundary(mode: LoopMode.count, remaining: 3),
        2,
      );
      // 第二遍结束，还剩 1 遍
      expect(
        LoopMath.remainingAfterBoundary(mode: LoopMode.count, remaining: 2),
        1,
      );
      // 第三遍结束 → 停
      expect(
        LoopMath.actionAfterBoundary(mode: LoopMode.count, remaining: 1),
        BoundaryAction.finish,
      );
      expect(
        LoopMath.remainingAfterBoundary(mode: LoopMode.count, remaining: 1),
        0,
      );
    });

    test('1 遍时第一次结束就停下', () {
      expect(
        LoopMath.actionAfterBoundary(mode: LoopMode.count, remaining: 1),
        BoundaryAction.finish,
      );
    });
  });

  group('状态快照文案', () {
    test('剩余遍数显示为「还差 N 遍」', () {
      const snapshot = PlaybackSnapshot(
        status: PlaybackStatus.playing,
        loopRegion: LoopRegion(startMs: 0, endMs: 3000),
        loopMode: LoopMode.count,
        loopCount: 3,
        loopRemaining: 2,
      );
      expect(snapshot.loopButtonLabel, '还差 2 遍');
      expect(snapshot.loopActive, isTrue);
    });

    test('播完后提示已播完', () {
      const snapshot = PlaybackSnapshot(
        status: PlaybackStatus.loopFinished,
        loopRegion: LoopRegion(startMs: 0, endMs: 3000),
        loopMode: LoopMode.count,
        loopCount: 3,
        loopRemaining: 0,
      );
      expect(snapshot.loopButtonLabel, '已播完 3 遍');
    });

    test('没有选区时循环未激活', () {
      const snapshot = PlaybackSnapshot(loopMode: LoopMode.infinite);
      expect(snapshot.loopActive, isFalse);
      expect(snapshot.isInsideLoop, isFalse);
    });
  });
}
