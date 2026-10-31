import '../../data/models/media_item.dart';

/// 播放器状态机的全部状态（需求 §9.4 要求状态集中管理）。
///
/// 状态迁移图：
/// ```
/// idle ──open──▶ loading ──▶ playing ⇄ paused
///                              │
///                              ├─ 到达 B 点 ──▶ gapCounting ──▶ playing（下一遍）
///                              │                     │
///                              │                     └─ 遍数用尽 ──▶ loopFinished
///                              └─ 文件播完 ──▶ completed
/// 任意状态 ──异常──▶ error
/// ```
enum PlaybackStatus {
  /// 还没打开任何媒体
  idle,

  /// 正在打开 / 缓冲
  loading,

  /// 播放中
  playing,

  /// 手动暂停
  paused,

  /// 跟读停顿倒计时中（需求 §3.3-8）
  gapCounting,

  /// 指定遍数播完，停在片段末尾等待用户操作（需求 §3.1-3）
  loopFinished,

  /// 播放到文件末尾自动暂停（需求 §4.2）
  completed,

  /// 出错
  error;

  bool get isPlaying => this == PlaybackStatus.playing;

  /// 是否处于「用户可感知的暂停」：这些状态下主按钮应显示播放图标
  bool get isIdleLike =>
      this == PlaybackStatus.paused ||
      this == PlaybackStatus.loopFinished ||
      this == PlaybackStatus.completed ||
      this == PlaybackStatus.idle ||
      this == PlaybackStatus.error;

  String get label => switch (this) {
        PlaybackStatus.idle => '未加载',
        PlaybackStatus.loading => '加载中',
        PlaybackStatus.playing => '播放中',
        PlaybackStatus.paused => '已暂停',
        PlaybackStatus.gapCounting => '跟读停顿',
        PlaybackStatus.loopFinished => '循环已完成',
        PlaybackStatus.completed => '已播完',
        PlaybackStatus.error => '播放出错',
      };
}

/// AB 片段区间。
class LoopRegion {
  const LoopRegion({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  int get lengthMs => endMs - startMs;

  /// 是否是合法区间（B 必须大于 A）
  bool get isValid => endMs > startMs;

  bool contains(int ms) => ms >= startMs && ms < endMs;

  /// 允许轻微超出，用于边界判定容差
  bool nearEnd(int ms, int toleranceMs) => ms >= endMs - toleranceMs;

  LoopRegion clampTo(int durationMs) {
    final max = durationMs > 0 ? durationMs : endMs;
    final start = startMs.clamp(0, max);
    final end = endMs.clamp(0, max);
    return LoopRegion(startMs: start, endMs: end);
  }

  @override
  bool operator ==(Object other) =>
      other is LoopRegion && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  @override
  String toString() => 'LoopRegion($startMs → $endMs)';
}

/// 播放器对外暴露的不可变状态快照。
///
/// UI 只订阅这个对象，所有状态变化都在 [PlaybackEngine] 内部产生，
/// 避免「播放器状态散落各处导致循环行为错乱」（需求 §9.4）。
class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.status = PlaybackStatus.idle,
    this.positionMs = 0,
    this.durationMs = 0,
    this.speed = 1.0,
    this.buffering = false,
    this.loopRegion,
    this.loopMode = LoopMode.off,
    this.loopCount = 1,
    this.loopRemaining,
    this.gapSeconds = 0,
    this.gapRemaining,
    this.errorMessage,
    this.mediaId,
    this.mediaName,
    this.mediaUri,
    this.isVideo = true,
  });

  final PlaybackStatus status;
  final int positionMs;
  final int durationMs;
  final double speed;
  final bool buffering;

  /// 当前生效的循环区间。同一时刻只存在一个（需求 §4.1）
  final LoopRegion? loopRegion;

  final LoopMode loopMode;

  /// 设定遍数
  final int loopCount;

  /// 剩余遍数；无限循环时为 null
  final int? loopRemaining;

  /// 跟读停顿档位（秒），0 表示关闭
  final int gapSeconds;

  /// 停顿倒计时剩余秒数
  final int? gapRemaining;

  final String? errorMessage;

  final int? mediaId;
  final String? mediaName;
  final String? mediaUri;
  final bool isVideo;

  bool get hasMedia => mediaId != null;
  bool get isPlaying => status == PlaybackStatus.playing;

  /// 循环是否处于「已启用」语义
  bool get loopActive => loopRegion != null && loopMode != LoopMode.off;

  bool get isInsideLoop {
    final region = loopRegion;
    if (region == null) return false;
    return region.contains(positionMs);
  }

  double get progressRatio {
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  /// 循环按钮上的文案（需求 §3.1-3 要求显示剩余遍数）
  String get loopButtonLabel {
    if (loopRegion == null || loopMode == LoopMode.off) return '循环片段';
    return switch (loopMode) {
      LoopMode.infinite => '无限循环中',
      LoopMode.count => switch (loopRemaining) {
          null => '循环 $loopCount 遍',
          0 => '已播完 $loopCount 遍',
          final left => '还差 $left 遍',
        },
      LoopMode.off => '循环片段',
    };
  }

  PlaybackSnapshot copyWith({
    PlaybackStatus? status,
    int? positionMs,
    int? durationMs,
    double? speed,
    bool? buffering,
    LoopRegion? loopRegion,
    bool clearLoopRegion = false,
    LoopMode? loopMode,
    int? loopCount,
    int? loopRemaining,
    bool clearLoopRemaining = false,
    int? gapSeconds,
    int? gapRemaining,
    bool clearGapRemaining = false,
    String? errorMessage,
    bool clearError = false,
    int? mediaId,
    String? mediaName,
    String? mediaUri,
    bool? isVideo,
  }) {
    return PlaybackSnapshot(
      status: status ?? this.status,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      speed: speed ?? this.speed,
      buffering: buffering ?? this.buffering,
      loopRegion: clearLoopRegion ? null : (loopRegion ?? this.loopRegion),
      loopMode: loopMode ?? this.loopMode,
      loopCount: loopCount ?? this.loopCount,
      loopRemaining:
          clearLoopRemaining ? null : (loopRemaining ?? this.loopRemaining),
      gapSeconds: gapSeconds ?? this.gapSeconds,
      gapRemaining: clearGapRemaining ? null : (gapRemaining ?? this.gapRemaining),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      mediaId: mediaId ?? this.mediaId,
      mediaName: mediaName ?? this.mediaName,
      mediaUri: mediaUri ?? this.mediaUri,
      isVideo: isVideo ?? this.isVideo,
    );
  }
}
