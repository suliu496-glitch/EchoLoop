import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/duration_utils.dart';
import '../../data/models/media_item.dart' show LoopMode;
import 'loop_math.dart';
import 'playable_source_resolver.dart';
import 'playback_clock.dart';
import 'playback_state.dart';

/// 播放引擎：全应用唯一的播放状态源。
///
/// ## 一、状态单向流动
///
/// 外部只能通过本类的方法改变状态，UI 只订阅 [snapshots]；
/// media_kit 的各个 stream 只作为「输入」，不直接改 UI 状态。
/// 这样才不会出现「内核说在播、界面显示暂停」这种两份状态打架的情况。
///
/// ## 二、循环边界的三层判定（这是精度问题的根治方案）
///
/// 一开始只靠内核回报的播放位置判断「有没有到 B 点」，结果很不精确：
/// 位置回调的间隔由解码器决定，音频上常常几十到几百毫秒才跳一次，
/// 拿这种粗颗粒的位置去切句子，有的句子被切掉尾巴，有的多播一截。
///
/// 现在改成三层：
///
/// 1. **高精度时钟 [PlaybackClock]**：自己按「真实经过时长 × 倍速」推算位置，
///    粒度由 20ms 轮询决定，完全不依赖内核回调频率。
/// 2. **一次性精确计时器**：按算出来的剩余时长精准唤醒，省掉轮询空转。
/// 3. **唤醒后复核**：用估算位置再确认一遍，没到就重排一小段继续等。
///    绝不在没播完的时候提前切，宁可多等几毫秒。
///
/// 容差方向始终是「宁可多播」：目标触发点定在 `B + 30ms`，
/// 暂停本身还有十几毫秒延迟，正好抵消，句子尾巴不会被吃掉。
///
/// ## 三、循环生效范围
///
/// 用户主动跳到 B 点之后（例如点字幕列表的下一句），循环会暂时失效，
/// 否则一跨进区间就被旧选区拽回 A 点，体验很糟。跳回区间内或用
/// [startLoop] 会重新激活。
class PlaybackEngine {
  PlaybackEngine({required PlayableSourceResolver resolver, Player? player})
      : _resolver = resolver,
        _player = player ?? Player() {
    videoController = VideoController(_player);
    _bindPlayerStreams();
  }

  final PlayableSourceResolver _resolver;
  final Player _player;

  /// 交给 `Video(controller: ...)` 使用；纯音频时界面不渲染它。
  late final VideoController videoController;

  final StreamController<PlaybackSnapshot> _controller =
      StreamController<PlaybackSnapshot>.broadcast();

  /// 状态流。UI 通过 Riverpod 订阅它。
  Stream<PlaybackSnapshot> get snapshots => _controller.stream;

  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  PlaybackSnapshot get snapshot => _snapshot;

  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// 高精度播放时钟，循环判定与界面位置都以它为准。
  final PlaybackClock _clock = PlaybackClock();

  // ---- 循环引擎内部状态 ----
  Timer? _loopTimer;
  Timer? _pollTimer;
  Timer? _gapTimer;
  Completer<void>? _gapCompleter;
  bool _gapRunning = false;
  int _gapGeneration = 0;

  /// 循环是否被用户的手动跳转临时压制（跳到 B 点之后时置位）
  bool _loopSuppressed = false;

  /// 正在处理循环边界：期间要屏蔽 playing stream 的副作用
  bool _handlingBoundary = false;

  int _lastEmitAt = 0;
  String? _currentUri;
  bool _disposed = false;

  // ---- 对外回调，用于把跟读停顿与录音服务接起来 ----
  void Function(int gapSeconds)? onGapStart;
  void Function()? onGapEnd;
  void Function()? onLoopFinished;

  // ------------------------------------------------------------------
  // 生命周期
  // ------------------------------------------------------------------

  void _bindPlayerStreams() {
    _subscriptions.add(_player.stream.position.listen((position) {
      final ms = position.inMilliseconds;
      // 内核只负责校正，不当作唯一真相
      _clock.correctFromKernel(ms);
      // 停顿倒计时期间位置钉在 B 点，不接受内核回传，否则界面进度会乱跳
      if (_snapshot.status == PlaybackStatus.gapCounting) return;
      _emitPositionThrottled();
    }));

    _subscriptions.add(_player.stream.duration.listen((duration) {
      final ms = duration.inMilliseconds;
      if (ms <= 0 || ms == _snapshot.durationMs) return;
      _update(durationMs: ms);
    }));

    _subscriptions.add(_player.stream.playing.listen((playing) {
      if (_handlingBoundary || _disposed) return;
      if (playing) {
        if (_snapshot.status != PlaybackStatus.playing) {
          _update(status: PlaybackStatus.playing, clearError: true);
        }
        _clock.startAt(_clock.positionMs, speed: _snapshot.speed);
        _armLoop();
      } else {
        // 只有「本来是播放中」才认为是暂停；循环停顿等状态不受影响
        if (_snapshot.status == PlaybackStatus.playing) {
          _clock.stop();
          _update(status: PlaybackStatus.paused);
        }
      }
    }));

    _subscriptions.add(_player.stream.buffering.listen((buffering) {
      // 卡顿时音频没往前走，时钟必须一起冻结，否则会把「卡了 1 秒」算成
      // 「播了 1 秒」，于是误判越过 B 点，句子被切掉
      if (buffering) {
        _clock.stop();
      } else if (_snapshot.isPlaying) {
        _clock.startAt(_clock.positionMs, speed: _snapshot.speed);
      }
      if (buffering != _snapshot.buffering) {
        _update(buffering: buffering);
      }
    }));

    _subscriptions.add(_player.stream.completed.listen((completed) {
      if (!completed || _disposed) return;
      if (_handlingBoundary) return;
      // B 点处于媒体末尾时，播放器可能先停止，时钟无法再走到 B + 容差。
      // 以播放完成事件确认这一遍已经结束，直接执行正常的循环边界流程。
      if (_snapshot.loopActive && !_loopSuppressed) {
        if (_snapshot.status != PlaybackStatus.loopFinished &&
            _snapshot.status != PlaybackStatus.gapCounting) {
          unawaited(_onLoopBoundary(reachedEndOfMedia: true));
        }
        return;
      }
      _clock.stop();
      _update(
        status: PlaybackStatus.completed,
        positionMs: _snapshot.durationMs,
      );
    }));

    _subscriptions.add(_player.stream.error.listen((message) {
      if (message.trim().isEmpty || _disposed) return;
      _update(
        status: PlaybackStatus.error,
        errorMessage: _friendlyPlaybackError(message),
      );
    }));
  }

  /// 打开一个媒体文件。
  ///
  /// 顺序刻意做成「先 open(play:false) → 设置倍速 → 定位 → 再 play」，
  /// 这样倍速与起始位置一定是确定的，不会出现「先按 1.0 播了一小段再变速」的抖动。
  Future<void> open({
    required int mediaId,
    required String uri,
    required String name,
    required bool isVideo,
    int startPositionMs = 0,
    bool autoPlay = true,
    LoopRegion? loopRegion,
    LoopMode loopMode = LoopMode.off,
    int loopCount = 1,
    int gapSeconds = 0,
    double speed = AppConstants.defaultSpeed,
  }) async {
    await _releaseCurrentSource();

    _snapshot = PlaybackSnapshot(
      status: PlaybackStatus.loading,
      mediaId: mediaId,
      mediaName: name,
      mediaUri: uri,
      isVideo: isVideo,
      speed: speed,
      loopRegion: loopRegion,
      loopMode: loopRegion == null ? LoopMode.off : loopMode,
      loopCount: loopCount,
      loopRemaining:
          loopRegion != null && loopMode == LoopMode.count ? loopCount : null,
      gapSeconds: gapSeconds,
    );
    _clock.seekTo(startPositionMs);
    _loopSuppressed = false;
    _currentUri = uri;
    _emit();

    try {
      final path = await _resolver.resolve(uri);
      await _player.open(Media(path), play: false);
      await _player.setRate(speed);
      if (startPositionMs > 0) {
        await _player.seek(Duration(milliseconds: startPositionMs));
      }
      _startPolling();
      if (autoPlay) {
        await _player.play();
        _clock.startAt(startPositionMs, speed: speed);
      } else {
        _update(status: PlaybackStatus.paused);
      }
      _armLoop();
    } catch (error) {
      _update(
        status: PlaybackStatus.error,
        errorMessage: humanizeError(error),
      );
    }
  }

  /// 关闭当前媒体（退出播放页时调用）。
  Future<void> close() async {
    await _releaseCurrentSource();
    _snapshot = const PlaybackSnapshot();
    _emit();
  }

  Future<void> dispose() async {
    _disposed = true;
    _cancelAllTimers();
    await _releaseCurrentSource();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _controller.close();
    await _player.dispose();
  }

  Future<void> _releaseCurrentSource() async {
    final uri = _currentUri;
    _currentUri = null;
    _cancelAllTimers();
    _loopSuppressed = false;
    _gapRunning = false;
    _gapGeneration++;
    _clock.stop();
    if (uri != null) {
      await _resolver.release(uri);
    }
  }

  // ------------------------------------------------------------------
  // 播放控制
  // ------------------------------------------------------------------

  Future<void> play() async {
    if (!_snapshot.hasMedia) return;

    // 指定遍数播完后再次按播放 = 再来一组（需求 §3.1-3「等待用户操作」）
    if (_snapshot.status == PlaybackStatus.loopFinished &&
        _snapshot.loopRegion != null) {
      await startLoop();
      return;
    }
    if (_snapshot.status == PlaybackStatus.completed) {
      await seekTo(0, userInitiated: true);
    }

    _update(status: PlaybackStatus.playing, clearError: true);
    await _player.setRate(_snapshot.speed);
    await _player.play();
    _clock.startAt(_clock.positionMs, speed: _snapshot.speed);
    _armLoop();
  }

  Future<void> pause() async {
    _loopTimer?.cancel();
    _loopTimer = null;
    _cancelGap();
    await _player.pause();
    _clock.stop();
    _update(
      status: PlaybackStatus.paused,
      clearGapRemaining: true,
      clearError: true,
    );
  }

  Future<void> togglePlay() async {
    if (_snapshot.status == PlaybackStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }

  /// 跳转到指定毫秒位置。
  Future<void> seekTo(int milliseconds, {bool userInitiated = true}) async {
    if (!_snapshot.hasMedia) return;
    final duration = _snapshot.durationMs;
    final upperBound = duration > 0 ? duration : milliseconds;
    final target = milliseconds.clamp(0, upperBound < 0 ? 0 : upperBound);

    // 从「循环已完成」状态手动跳走，说明用户不打算继续这一组循环了
    final status = _snapshot.status == PlaybackStatus.loopFinished && userInitiated
        ? PlaybackStatus.paused
        : _snapshot.status;

    _clock.seekTo(target);
    if (_snapshot.isPlaying) {
      _clock.startAt(target, speed: _snapshot.speed);
    }
    _update(positionMs: target, status: status);

    await _player.seek(Duration(milliseconds: target));

    // 跳到 B 点之后就不再被这个选区「抓回去」，跳回来则重新激活
    final region = _snapshot.loopRegion;
    _loopSuppressed = userInitiated &&
        region != null &&
        LoopMath.shouldSuppressLoop(positionMs: target, region: region);
    _armLoop();
  }

  /// 快捷微调：正数前进，负数后退，单位秒（需求 §3.1-4）。
  Future<void> seekBySeconds(double seconds) async {
    final delta = (seconds * 1000).round();
    await seekTo(_clock.positionMs + delta, userInitiated: true);
  }

  /// 设置倍速。变速由 libmpv 的 pitch correction 完成，保证人声不变调。
  Future<void> setSpeed(double speed) async {
    if (speed <= 0 || speed == _snapshot.speed) return;
    _update(speed: speed);
    await _player.setRate(speed);
    // 先让时钟在旧倍速下把当前位置结算清楚，再换倍速，否则历史时间会被错误换算
    _clock.setSpeed(speed);
    _armLoop();
  }

  /// 设置跟读停顿时长（秒），0 表示关闭。
  Future<void> setGapSeconds(int seconds) async {
    if (seconds == _snapshot.gapSeconds) return;
    _update(gapSeconds: seconds);
  }

  // ------------------------------------------------------------------
  // 循环区间
  // ------------------------------------------------------------------

  /// 设置 AB 片段。会自动保证 A < B，并且在播放中**立刻生效**。
  ///
  /// 「立刻生效」是这里最关键的行为：以前调完 A/B 要等播放自然走到 B 才起作用，
  /// 用户感觉是「改了没用」。现在分三种情况处理：
  ///
  /// - 当前位置已经越过新的 B：马上回到 A 重新开始；
  /// - 当前位置在新的 A 之前：跳到新的 A 开始；
  /// - 位置就在区间里：什么都不用做，重排计时器即可。
  Future<void> setLoopRegion(
    int startMs,
    int endMs, {
    LoopMode? mode,
    int? count,
  }) async {
    if (!_snapshot.hasMedia) return;
    var start = startMs;
    var end = endMs;
    if (start > end) {
      final temp = start;
      start = end;
      end = temp;
    }
    final duration = _snapshot.durationMs;
    if (duration > 0) {
      start = start.clamp(0, duration);
      end = end.clamp(0, duration);
    }
    final region = LoopRegion(startMs: start, endMs: end);
    if (!region.isValid) return;

    final nextMode = mode ??
        (_snapshot.loopMode == LoopMode.off
            ? LoopMode.infinite
            : _snapshot.loopMode);
    final nextCount = count ?? _snapshot.loopCount;

    final wasPlaying = _snapshot.status == PlaybackStatus.playing;
    final position = _clock.positionMs;

    // 新选区一律重新激活循环（用户刚圈完，肯定希望它生效）
    _loopSuppressed = false;

    _update(
      loopRegion: region,
      loopMode: nextMode,
      loopCount: nextCount,
      loopRemaining: nextMode == LoopMode.count ? nextCount : null,
      clearLoopRemaining: nextMode != LoopMode.count,
      clearGapRemaining: true,
    );

    if (wasPlaying &&
        LoopMath.shouldRewindToStart(positionMs: position, region: region)) {
      // 位置落在新区间外：直接归位到 A 继续播，让改动「可见」
      await _beginPass(rewindTo: region.startMs);
      return;
    }
    _armLoop();
  }

  /// 只调整 A 或 B 中的一个点。
  Future<void> setLoopStart(int startMs) async {
    final region = _snapshot.loopRegion;
    if (region == null) return;
    await setLoopRegion(startMs, region.endMs);
  }

  Future<void> setLoopEnd(int endMs) async {
    final region = _snapshot.loopRegion;
    if (region == null) return;
    await setLoopRegion(region.startMs, endMs);
  }

  /// 切换循环模式（无限 / 指定遍数 / 关闭）。
  Future<void> setLoopMode(LoopMode mode, {int? count}) async {
    final nextCount = count ?? _snapshot.loopCount;
    _update(
      loopMode: mode,
      loopCount: nextCount,
      loopRemaining: mode == LoopMode.count ? nextCount : null,
      clearLoopRemaining: mode != LoopMode.count,
      clearGapRemaining: true,
    );
    if (mode == LoopMode.off) {
      _loopTimer?.cancel();
      _loopTimer = null;
      _cancelGap();
    } else {
      _loopSuppressed = false;
      _armLoop();
    }
  }

  /// 清除选区，退出循环。
  Future<void> clearLoopRegion() async {
    _loopTimer?.cancel();
    _loopTimer = null;
    _loopSuppressed = false;
    _cancelGap();
    _update(
      clearLoopRegion: true,
      loopMode: LoopMode.off,
      clearLoopRemaining: true,
      clearGapRemaining: true,
    );
  }

  /// 显式开始循环：回到 A 点，遍数清零重来。
  Future<void> startLoop() async {
    final region = _snapshot.loopRegion;
    if (region == null || _snapshot.loopMode == LoopMode.off) return;
    _loopSuppressed = false;
    _update(clearGapRemaining: true, clearError: true);
    await _beginPass(rewindTo: region.startMs, resetCounter: true);
  }

  // ------------------------------------------------------------------
  // 循环边界判定（核心）
  // ------------------------------------------------------------------

  /// 循环当前是否具备触发条件。
  bool get _loopEnabled {
    final region = _snapshot.loopRegion;
    return region != null &&
        _snapshot.loopMode != LoopMode.off &&
        _snapshot.status == PlaybackStatus.playing &&
        !_handlingBoundary &&
        !_loopSuppressed;
  }

  /// 排一次性精确计时器，按算出来的剩余时长精准唤醒。
  ///
  /// 它只是「省电优化」：真正的兜底是 20ms 轮询，所以这里算错也不会丢边界。
  void _armLoop() {
    _loopTimer?.cancel();
    _loopTimer = null;
    if (!_loopEnabled) return;

    final region = _snapshot.loopRegion!;
    final position = _clock.positionMs;
    if (position < region.startMs) return; // 还没进区间，交给轮询接管

    final waitMs = LoopMath.msUntilBoundary(
      positionMs: position,
      region: region,
      speed: _snapshot.speed,
    );
    if (waitMs == null || waitMs <= 0) return; // 已经越过，轮询会立刻收口

    _loopTimer = Timer(
      Duration(
        milliseconds: waitMs.clamp(AppConstants.minLoopTimerMs, 3600000),
      ),
      _onLoopBoundary,
    );
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(
      AppConstants.loopPollInterval,
      (_) => _pollTick(),
    );
  }

  /// 20ms 一次的位置检查。逻辑极轻（两次整数比较），但它是精度的底座。
  void _pollTick() {
    if (_disposed || !_loopEnabled) return;
    final region = _snapshot.loopRegion!;
    final position = _clock.positionMs;
    if (position < region.startMs) return;
    if (LoopMath.shouldTrigger(positionMs: position, region: region)) {
      _onLoopBoundary();
    }
  }

  /// 到达 B 点：暂停 → 归位到 B → 按模式决定「再来一遍」还是「停在末尾」。
  Future<void> _onLoopBoundary({bool reachedEndOfMedia = false}) async {
    if (_handlingBoundary || _disposed || _loopSuppressed) return;
    if (!reachedEndOfMedia && _snapshot.status != PlaybackStatus.playing) return;
    final region = _snapshot.loopRegion;
    if (region == null || _snapshot.loopMode == LoopMode.off) return;

    // 复核：估算位置显示还没到 B 点（计时器提前唤醒或时钟抖动），
    // 就重排一小段继续等。绝不提前切，否则句子尾巴会被吃掉。
    final target = region.endMs + AppConstants.loopTriggerToleranceMs;
    final position = _clock.positionMs;
    if (!reachedEndOfMedia && position < target) {
      final remainMs = DurationUtils.realDurationMs(target - position, _snapshot.speed);
      if (remainMs > AppConstants.minLoopTimerMs) {
        _loopTimer?.cancel();
        _loopTimer = Timer(Duration(milliseconds: remainMs), _onLoopBoundary);
        return;
      }
    }

    _handlingBoundary = true;
    _loopTimer?.cancel();
    _loopTimer = null;

    try {
      await _player.pause();
      _clock.stop();
      await _player.seek(Duration(milliseconds: region.endMs));
      _clock.seekTo(region.endMs);

      final action = LoopMath.actionAfterBoundary(
        mode: _snapshot.loopMode,
        remaining: _snapshot.loopRemaining,
      );
      final nextRemaining = LoopMath.remainingAfterBoundary(
        mode: _snapshot.loopMode,
        remaining: _snapshot.loopRemaining,
      );

      switch (action) {
        case BoundaryAction.nextPass:
          _update(positionMs: region.endMs);
          await _runGapThenNextPass();
          break;
        case BoundaryAction.countDown:
          _update(loopRemaining: nextRemaining, positionMs: region.endMs);
          await _runGapThenNextPass();
          break;
        case BoundaryAction.finish:
          // 需求 §3.1-3：循环完设定遍数后自动暂停并停在片段末尾，不自动往下播
          _update(
            status: PlaybackStatus.loopFinished,
            loopRemaining: 0,
            positionMs: region.endMs,
            clearGapRemaining: true,
          );
          onLoopFinished?.call();
          break;
      }
    } catch (error) {
      _update(status: PlaybackStatus.error, errorMessage: humanizeError(error));
    } finally {
      _handlingBoundary = false;
    }
  }

  /// 边界之后：有停顿就先倒计时（顺便留出跟读与录音的空隙），否则直接开下一遍。
  Future<void> _runGapThenNextPass() async {
    final gap = _snapshot.gapSeconds;
    if (gap <= 0) {
      await _beginPass();
      return;
    }

    _gapRunning = true;
    _gapCompleter = Completer<void>();
    final generation = ++_gapGeneration;
    onGapStart?.call(gap);
    _update(status: PlaybackStatus.gapCounting, gapRemaining: gap);

    // 用 200ms 一跳自己累计，而不是每秒一跳。
    // 每秒计时器会受调度延迟影响逐秒累积误差，倒计时结束可能晚几十上百毫秒，
    // 而这几百毫秒正好是下一遍该开口的时机，晚一点体验就很明显。
    const tickMs = 200;
    final totalMs = gap * 1000;
    _gapTimer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      final leftMs = totalMs - timer.tick * tickMs;
      final seconds = (leftMs / 1000).ceil();
      if (seconds <= 0) {
        _update(gapRemaining: 0);
        _finishGap();
      } else if (seconds != _snapshot.gapRemaining) {
        _update(gapRemaining: seconds);
      }
    });

    final completer = _gapCompleter!;
    await completer.future;

    // 代次号变了说明期间被暂停 / 切文件 / 清选区打断，不能自行继续
    if (generation != _gapGeneration) return;
    await _beginPass();
  }

  /// 开始新的一遍。
  ///
  /// [rewindTo] 为空时回到区间起点。[resetCounter] 用于「再练一组」时重置遍数。
  Future<void> _beginPass({int? rewindTo, bool resetCounter = false}) async {
    if (_disposed) return;
    final region = _snapshot.loopRegion;
    if (region == null || _snapshot.loopMode == LoopMode.off) return;

    final target = rewindTo ?? region.startMs;

    await _player.seek(Duration(milliseconds: target));
    _clock.seekTo(target);

    _update(
      status: PlaybackStatus.playing,
      positionMs: target,
      loopRemaining: resetCounter && _snapshot.loopMode == LoopMode.count
          ? _snapshot.loopCount
          : null,
      clearLoopRemaining: _snapshot.loopMode != LoopMode.count,
      clearGapRemaining: true,
      clearError: true,
    );

    // 循环切换时倍速必须保持（需求 §3.1-2），每次都重新下发防止内核重置
    await _player.setRate(_snapshot.speed);
    await _player.play();
    // 时钟在真正开播之后才起步，这样锚点与「声音实际开始走」的时刻对齐，
    // 不会把 seek 到 play 之间的调度延迟算成已经播过的时长
    _clock.startAt(target, speed: _snapshot.speed);
    _armLoop();
  }

  void _finishGap() {
    _gapTimer?.cancel();
    _gapTimer = null;
    if (_gapRunning) {
      _gapRunning = false;
      onGapEnd?.call();
    }
    final completer = _gapCompleter;
    _gapCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _cancelGap() {
    if (!_gapRunning && _gapCompleter == null) return;
    _gapGeneration++;
    _finishGap();
  }

  void _cancelAllTimers() {
    _loopTimer?.cancel();
    _loopTimer = null;
    _gapTimer?.cancel();
    _gapTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    final completer = _gapCompleter;
    _gapCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  // ------------------------------------------------------------------
  // 状态发布
  // ------------------------------------------------------------------

  void _update({
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
  }) {
    if (_disposed) return;
    _snapshot = _snapshot.copyWith(
      status: status,
      positionMs: positionMs,
      durationMs: durationMs,
      speed: speed,
      buffering: buffering,
      loopRegion: loopRegion,
      clearLoopRegion: clearLoopRegion,
      loopMode: loopMode,
      loopCount: loopCount,
      loopRemaining: loopRemaining,
      clearLoopRemaining: clearLoopRemaining,
      gapSeconds: gapSeconds,
      gapRemaining: gapRemaining,
      clearGapRemaining: clearGapRemaining,
      errorMessage: errorMessage,
      clearError: clearError,
    );
    _emit();
  }

  /// 位置更新走节流：估算位置每 20ms 都在变，但界面 10Hz 就够了。
  void _emitPositionThrottled() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastEmitAt < 80) return;
    _lastEmitAt = now;
    _update(positionMs: _clock.positionMs);
  }

  void _emit() {
    if (_disposed || _controller.isClosed) return;
    _controller.add(_snapshot);
  }

  /// 把内核的英文报错换成能看懂的中文提示（需求 §7「不支持的编码给出明确提示而非黑屏」）。
  String _friendlyPlaybackError(String raw) {
    final message = raw.trim();
    final lower = message.toLowerCase();
    if (lower.contains('format') ||
        lower.contains('codec') ||
        lower.contains('decode')) {
      return '这个文件的编码格式不被支持，试试转成 MP4(H.264) 或 MP3 再导入。';
    }
    if (lower.contains('no such file') || lower.contains('not found')) {
      return '文件找不到了，可能已被移动或删除，请重新导入。';
    }
    if (lower.contains('permission') || lower.contains('denied')) {
      return '没有读取该文件的权限，请重新导入并允许访问。';
    }
    return '播放失败：$message';
  }
}
