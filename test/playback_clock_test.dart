import 'package:echoloop/domain/playback/playback_clock.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可控时间源：测试里手动推进时间，不依赖真实时钟。
class _FakeTime {
  int nowMs = 1000000;

  int read() => nowMs;

  void advance(int ms) => nowMs += ms;
}

void main() {
  late _FakeTime fake;
  late PlaybackClock clock;

  setUp(() {
    fake = _FakeTime();
    clock = PlaybackClock(nowMilliseconds: fake.read);
  });

  group('基本走时', () {
    test('1 倍速下真实时间与音频时间同步前进', () {
      clock.startAt(1000);
      fake.advance(500);
      expect(clock.positionMs, 1500);
      fake.advance(250);
      expect(clock.positionMs, 1750);
    });

    test('0.5 倍速下走时减半（这是循环精度最容易错的地方）', () {
      clock.startAt(0, speed: 0.5);
      fake.advance(1000);
      // 真实过 1 秒，音频只走了 0.5 秒
      expect(clock.positionMs, 500);
    });

    test('2 倍速下走时加倍', () {
      clock.startAt(0, speed: 2.0);
      fake.advance(1000);
      expect(clock.positionMs, 2000);
    });

    test('未启动时停在锚点不动', () {
      clock.seekTo(3000);
      fake.advance(5000);
      expect(clock.positionMs, 3000);
      expect(clock.isRunning, isFalse);
    });
  });

  group('暂停与恢复', () {
    test('暂停会冻结在当前估算位置', () {
      clock.startAt(1000);
      fake.advance(400);
      clock.stop();
      expect(clock.positionMs, 1400);

      // 暂停期间时间流逝，位置不能继续涨
      fake.advance(3000);
      expect(clock.positionMs, 1400);
    });

    test('暂停后从冻结位置恢复，不会把暂停时长算进去', () {
      clock.startAt(1000);
      fake.advance(400);
      clock.stop();
      fake.advance(3000);

      // 模拟缓冲结束：从当前位置重新起步
      clock.startAt(clock.positionMs);
      fake.advance(200);
      expect(clock.positionMs, 1600);
    });
  });

  group('变速', () {
    test('变速前先结算历史时间，避免旧时间被新倍速错误换算', () {
      clock.startAt(0, speed: 1.0);
      fake.advance(1000);
      expect(clock.positionMs, 1000);

      // 切到 0.5 倍速
      clock.setSpeed(0.5);
      fake.advance(1000);
      // 前 1 秒按 1 倍速走了 1000，后 1 秒按 0.5 倍速只走 500
      expect(clock.positionMs, 1500);
    });

    test('非法倍速回退成 1 倍速，不会出现负数或除零', () {
      clock.startAt(0, speed: 0);
      fake.advance(500);
      expect(clock.positionMs, 500);
    });
  });

  group('内核校正', () {
    test('偏差在阈值内时不重锚，保持估算平滑', () {
      clock.startAt(1000);
      fake.advance(500);
      // 估算 1500，内核说 1480，差 20ms，属于抖动
      final realigned = clock.correctFromKernel(1480);
      expect(realigned, isFalse);
      expect(clock.positionMs, 1500);
    });

    test('偏差超过阈值时重锚到内核位置', () {
      clock.startAt(1000);
      fake.advance(2000);
      expect(clock.positionMs, 3000);

      // 内核说其实只在 2200，差了 800ms，必须纠正
      final realigned = clock.correctFromKernel(2200);
      expect(realigned, isTrue);
      expect(clock.positionMs, 2200);

      // 重锚之后继续按真实时间走
      fake.advance(300);
      expect(clock.positionMs, 2500);
    });

    test('暂停状态下内核位置直接采纳（拖动进度条的场景）', () {
      clock.stop();
      clock.correctFromKernel(8888);
      expect(clock.positionMs, 8888);
    });
  });

  group('循环边界的实际含义', () {
    test('0.5 倍速下 3 秒音频要等 6 秒真实时间才到 B 点', () {
      const regionStart = 0;
      const regionEnd = 3000;
      const tolerance = 30;

      clock.startAt(regionStart, speed: 0.5);
      // 5 秒真实时间过去，音频只走到 2500，还没到 B
      fake.advance(5000);
      expect(clock.positionMs, 2500);
      expect(
        clock.positionMs >= regionEnd + tolerance,
        isFalse,
        reason: '没到 B 点就不该触发循环',
      );

      // 再过 1.1 秒，音频到 3050，越过 B + 容差
      fake.advance(1060);
      expect(clock.positionMs, 3030);
      expect(clock.positionMs >= regionEnd + tolerance, isTrue);
    });
  });
}
