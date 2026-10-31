import '../../core/constants/app_constants.dart';
import '../../core/utils/duration_utils.dart';
import '../../data/models/media_item.dart' show LoopMode;
import 'playback_state.dart';

/// 到达 B 点之后该做什么。
enum BoundaryAction {
  /// 无限循环：直接开下一遍（或先走跟读停顿）
  nextPass,

  /// 指定遍数还有剩余：减一遍再播
  countDown,

  /// 指定遍数用尽：停在片段末尾等用户操作
  finish,
}

/// 循环边界的纯计算逻辑。
///
/// 刻意从 [PlaybackEngine] 里抽出来：引擎本身要持有 Player、计时器、流订阅，
/// 很难在单元测试里构造；而「什么时候该跳到 A 点」这种判定完全是数学问题，
/// 抽成纯函数后可以在 `flutter test` 里直接验证，不用真起一个播放器。
class LoopMath {
  LoopMath._();

  /// 离边界还有多少「真实时间」毫秒。
  ///
  /// 返回 null 表示当前不在区间内，不应该武装循环计时器。
  /// 注意要做倍速换算：0.5 倍速下同样一段音频要花两倍真实时间。
  static int? msUntilBoundary({
    required int positionMs,
    required LoopRegion region,
    required double speed,
    int toleranceMs = AppConstants.loopTriggerToleranceMs,
  }) {
    if (!region.contains(positionMs)) return null;
    // 多留一点容差，宁可多播几十毫秒，也不要把句子尾巴切掉
    final remainAudioMs = region.endMs + toleranceMs - positionMs;
    if (remainAudioMs <= 0) return 0;
    return DurationUtils.realDurationMs(remainAudioMs, speed);
  }

  /// 兜底轮询用：位置是否已经越过边界。
  static bool shouldTrigger({
    required int positionMs,
    required LoopRegion region,
    int toleranceMs = AppConstants.loopTriggerToleranceMs,
  }) {
    return positionMs >= region.endMs + toleranceMs;
  }

  /// 用户主动跳到 B 点之后时，这个选区应该暂时失效。
  ///
  /// 场景：循环练完一句，点字幕列表里的下一句想往后听。
  /// 如果不压制，播放位置一跨进旧区间就会被拽回 A 点，体验很糟。
  static bool shouldSuppressLoop({
    required int positionMs,
    required LoopRegion region,
  }) {
    return positionMs > region.endMs;
  }

  /// 循环模式下，「位置已经落到区间外」时应该立刻归位到 A。
  ///
  /// 用在播放中调整 A/B 的场景：把 B 往前挪（缩短片段）或者把 A 往后挪
  /// （去掉开头）之后，当前位置很可能已经不在新区间里了，这时必须马上回到 A，
  /// 否则用户会觉得「改了没用」。
  static bool shouldRewindToStart({
    required int positionMs,
    required LoopRegion region,
  }) {
    return positionMs >= region.endMs || positionMs < region.startMs;
  }

  /// 边界之后按模式决定动作。
  static BoundaryAction actionAfterBoundary({
    required LoopMode mode,
    required int? remaining,
  }) {
    if (mode == LoopMode.infinite) return BoundaryAction.nextPass;
    final left = (remaining ?? 1) - 1;
    return left > 0 ? BoundaryAction.countDown : BoundaryAction.finish;
  }

  /// 一遍播完后剩余的遍数（无限循环返回 null）。
  static int? remainingAfterBoundary({
    required LoopMode mode,
    required int? remaining,
  }) {
    if (mode == LoopMode.infinite) return null;
    final left = (remaining ?? 1) - 1;
    return left < 0 ? 0 : left;
  }
}
