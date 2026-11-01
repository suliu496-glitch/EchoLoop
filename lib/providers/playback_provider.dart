import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/duration_utils.dart';
import '../data/dao/media_dao.dart';
import '../data/models/app_settings.dart';
import '../data/models/media_item.dart';
import '../domain/playback/playback_engine.dart';
import '../domain/playback/playback_state.dart';
import '../domain/subtitles/subtitle_cue.dart';
import '../domain/playback/sentence_sequence.dart';
import '../services/background_playback_service.dart';
import '../services/recording_service.dart';
import 'core_providers.dart';
import 'settings_provider.dart';

enum MediaPlaybackMode { sequential, repeatOne, repeatAll }

final mediaPlaybackModeProvider = StateProvider<MediaPlaybackMode>(
  (ref) => MediaPlaybackMode.sequential,
);

/// 播放业务的对外入口。
///
/// 它是「引擎」与「界面 / 系统能力」之间的胶水：
/// - 向下：订阅 [PlaybackEngine.snapshots] 转成 Riverpod 状态；
/// - 向上：把播放状态同步到通知栏、持久化播放进度与循环区间；
/// - 侧向：把跟读停顿与录音服务接起来，把通知栏操作转成播放动作。
///
/// 引擎本身完全不知道数据库、通知、录音的存在，职责边界清晰。
class PlaybackNotifier extends StateNotifier<PlaybackSnapshot> {
  PlaybackNotifier({
    required PlaybackEngine engine,
    required MediaDao mediaDao,
    required SettingsNotifier settings,
    required BackgroundPlaybackService background,
    required RecordingService recorder,
    required MediaPlaybackMode Function() readMediaPlaybackMode,
  }) : _engine = engine,
       _mediaDao = mediaDao,
       _settings = settings,
       _background = background,
       _recorder = recorder,
       _readMediaPlaybackMode = readMediaPlaybackMode,
       super(const PlaybackSnapshot()) {
    _bindEngine();
    _bindBackgroundControls();
  }

  final PlaybackEngine _engine;
  final MediaDao _mediaDao;
  final SettingsNotifier _settings;
  final BackgroundPlaybackService _background;
  final RecordingService _recorder;
  final MediaPlaybackMode Function() _readMediaPlaybackMode;
  bool _handlingCompletion = false;

  StreamSubscription<PlaybackSnapshot>? _engineSubscription;
  Timer? _ticker;
  Timer? _compareTimer;

  int _tickCount = 0;
  int? _currentMediaId;
  String? _currentName;

  /// 播放队列：通知栏「上一片段 / 下一片段」按这个顺序切。
  List<MediaItem> _queue = const [];

  /// 录音是否因这次停顿而开启（避免误停用户后来的录音）
  bool _recordingForGap = false;

  List<SubtitleCue> _sentencePlaylist = const [];
  int _sentenceIndex = -1;
  bool _autoAdvanceCurrent = false;
  Future<void> _loopWrites = Future<void>.value();
  Future<void> _progressWrites = Future<void>.value();
  Future<void>? _leaveFuture;
  bool _leaving = false;

  /// 最近一次通知栏内容，用于去重，避免无意义的刷新
  String _lastNotificationKey = '';

  List<MediaItem> get queue => _queue;

  int get queueIndex {
    final id = _currentMediaId;
    if (id == null) return -1;
    return _queue.indexWhere((item) => item.id == id);
  }

  RecordingService get recorder => _recorder;

  void _bindEngine() {
    _engineSubscription = _engine.snapshots.listen(_onEngineSnapshot);
    _engine.onLoopFinished = _handleSentenceLoopFinished;

    // 跟读停顿开始：如果开了「停顿期间自动录音」，这里开麦
    _engine.onGapStart = (gapSeconds) {
      if (!_settings.effectiveRecordDuringGap) return;
      _recordingForGap = true;
      _recorder.start();
    };

    // 停顿结束：把录音收下来，供对比播放
    _engine.onGapEnd = () {
      if (!_recordingForGap) return;
      _recordingForGap = false;
      _recorder.stop();
    };
  }

  void _bindBackgroundControls() {
    _background.onToggle = (action) {
      if (action == 'toggle') togglePlay();
    };
    _background.onPrevious = previousMedia;
    _background.onNext = nextMedia;
    _background.onSpeedCycle = cycleSpeed;
    _background.onPlay = play;
    _background.onPause = pause;
    _background.onSeek = seekTo;
  }

  void _onEngineSnapshot(PlaybackSnapshot snapshot) {
    // 上一次的时长是 0 而这次有了，说明元数据刚解析出来，补记一次数据库时长
    final previous = state;
    state = snapshot;

    if (snapshot.status == PlaybackStatus.completed &&
        previous.status != PlaybackStatus.completed &&
        snapshot.mediaId == _currentMediaId) {
      unawaited(_handleMediaCompleted(snapshot.mediaId));
    }

    if (snapshot.durationMs > 0 && previous.durationMs == 0) {
      final id = snapshot.mediaId;
      if (id != null) {
        unawaited(_mediaDao.updateDurationIfMissing(id, snapshot.durationMs));
      }
    }

    if (snapshot.status == PlaybackStatus.loopFinished ||
        snapshot.status == PlaybackStatus.paused ||
        snapshot.status == PlaybackStatus.completed) {
      _persistProgress();
    }

    _syncTicker();
    _syncNotification();
  }

  // ------------------------------------------------------------------
  // 打开 / 切换媒体
  // ------------------------------------------------------------------

  /// 打开一个媒体。传入 [queue] 可以启用通知栏的上一段 / 下一段。
  Future<void> openMedia(
    MediaItem item, {
    List<MediaItem>? queue,
    bool autoPlay = true,
  }) async {
    final id = item.id;
    if (id == null) return;
    final closing = _leaveFuture;
    if (closing != null) await closing;
    await _loopWrites;
    final latest = await _mediaDao.findById(id);
    if (latest == null) return;
    if (queue != null && queue.isNotEmpty) _queue = queue;
    _cancelSentenceAdvance();

    final previousId = _engine.snapshot.mediaId;
    if (previousId != null) await _writeProgress(previousId, 0);
    await _writeProgress(id, 0);
    _cancelCompare();

    final settings = _settings.state;
    await _engine.open(
      mediaId: id,
      uri: latest.uri,
      name: latest.name,
      isVideo: latest.isVideo,
      startPositionMs: 0,
      autoPlay: autoPlay,
      loopRegion: latest.hasLoopRegion
          ? LoopRegion(startMs: latest.loopStartMs!, endMs: latest.loopEndMs!)
          : null,
      loopMode: latest.hasLoopRegion ? latest.loopMode : LoopMode.off,
      loopCount: latest.loopCount,
      gapSeconds: settings.gapSeconds,
      speed: settings.speed,
    );

    _currentMediaId = id;
    _currentName = latest.name;
    await _settings.setLastMediaId(id);
    await _background.start(
      title: latest.name,
      text: _progressText(_engine.snapshot),
      playing: _engine.snapshot.isPlaying,
      speed: _engine.snapshot.speed,
      positionMs: _engine.snapshot.positionMs,
      durationMs: _engine.snapshot.durationMs,
      keepAwake:
          _engine.snapshot.isPlaying ||
          _engine.snapshot.status == PlaybackStatus.gapCounting,
    );
  }

  Future<void> previousMedia() async {
    final index = queueIndex;
    if (index <= 0) return;
    await openMedia(_queue[index - 1]);
  }

  Future<void> nextMedia() async {
    final index = queueIndex;
    if (index < 0 || _queue.isEmpty) return;
    if (index < _queue.length - 1) {
      await openMedia(_queue[index + 1]);
    } else if (_readMediaPlaybackMode() == MediaPlaybackMode.repeatAll) {
      await openMedia(_queue.first);
    }
  }

  Future<void> _handleMediaCompleted(int? mediaId) async {
    if (_handlingCompletion || mediaId == null) return;
    _handlingCompletion = true;
    try {
      if (_readMediaPlaybackMode() == MediaPlaybackMode.repeatOne) {
        if (_currentMediaId != mediaId) return;
        await _engine.seekTo(0);
        await _engine.play();
      } else {
        await nextMedia();
      }
    } finally {
      _handlingCompletion = false;
    }
  }

  /// 离开播放页：停掉后台服务、落盘进度、释放文件描述符。
  Future<void> leavePlayer() {
    final pending = _leaveFuture;
    if (pending != null) return pending;
    final task = _leavePlayer();
    _leaveFuture = task;
    return task.whenComplete(() {
      if (identical(_leaveFuture, task)) _leaveFuture = null;
    });
  }

  Future<void> _leavePlayer() async {
    _leaving = true;
    _cancelSentenceAdvance();
    _cancelCompare();
    _ticker?.cancel();
    _ticker = null;
    final id = _engine.snapshot.mediaId;
    try {
      await _loopWrites;
      if (id != null) await _writeProgress(id, 0);
      await _background.stop();
      await _recorder.cancel();
      await _engine.close();
      _currentMediaId = null;
    } finally {
      _leaving = false;
    }
  }

  Future<void> waitForPlayerClosed() => _leaveFuture ?? Future<void>.value();

  // ------------------------------------------------------------------
  // 基础播放控制
  // ------------------------------------------------------------------

  Future<void> togglePlay() async {
    _cancelCompare();
    await _engine.togglePlay();
  }

  Future<void> play() async {
    _cancelCompare();
    await _engine.play();
  }

  Future<void> pause() async {
    _cancelCompare();
    await _engine.pause();
    await _persistProgress();
  }

  Future<void> seekTo(int milliseconds) async {
    _cancelSentenceAdvance();
    _cancelCompare();
    await _engine.seekTo(milliseconds);
  }

  Future<void> seekBySeconds(double seconds) async {
    _cancelSentenceAdvance();
    _cancelCompare();
    await _engine.seekBySeconds(seconds);
  }

  /// 倍速是**全局设置**（需求 §4.2）：改一次，之后打开别的文件也保持。
  Future<void> setSpeed(double speed) async {
    await _engine.setSpeed(speed);
    await _settings.setSpeed(speed);
  }

  Future<void> cycleSpeed() async {
    final presets = AppConstants.speedPresets;
    final index = presets.indexOf(state.speed);
    final next = index < 0
        ? AppConstants.defaultSpeed
        : presets[(index + 1) % presets.length];
    await setSpeed(next);
  }

  Future<void> setGapSeconds(int seconds) async {
    await _engine.setGapSeconds(seconds);
    await _settings.setGapSeconds(seconds);
  }

  // ------------------------------------------------------------------
  // 循环
  // ------------------------------------------------------------------

  Future<void> setLoopRegion(int startMs, int endMs) async {
    _cancelSentenceAdvance();
    final operation = _engine.setLoopRegion(startMs, endMs);
    final save = _persistLoop();
    await operation;
    await save;
  }

  Future<void> nudgeLoopStart(double deltaSeconds) async {
    _cancelSentenceAdvance();
    final region = _engine.snapshot.loopRegion;
    if (region == null) return;
    final next = region.startMs + (deltaSeconds * 1000).round();
    final operation = _engine.setLoopRegion(
      next.clamp(0, region.endMs - 100),
      region.endMs,
    );
    final save = _persistLoop();
    await operation;
    await save;
  }

  Future<void> nudgeLoopEnd(double deltaSeconds) async {
    _cancelSentenceAdvance();
    final region = _engine.snapshot.loopRegion;
    if (region == null) return;
    final next = region.endMs + (deltaSeconds * 1000).round();
    final operation = _engine.setLoopRegion(region.startMs, next);
    final save = _persistLoop();
    await operation;
    await save;
  }

  Future<void> setLoopMode(LoopMode mode, {int? count}) async {
    _cancelSentenceAdvance();
    final operation = _engine.setLoopMode(mode, count: count);
    final save = _persistLoop();
    await operation;
    if (count != null) await _settings.setLoopCount(count);
    await _settings.setLoopMode(mode);
    await save;
  }

  Future<void> clearLoopRegion() async {
    _cancelSentenceAdvance();
    _cancelCompare();
    final operation = _engine.clearLoopRegion();
    final save = _persistLoop();
    await operation;
    await save;
  }

  Future<void> startLoop() async {
    _cancelCompare();
    if (_engine.snapshot.loopRegion != null &&
        _engine.snapshot.loopMode == LoopMode.off) {
      final preferred = _settings.state.loopMode;
      final operation = _engine.setLoopMode(
        preferred == LoopMode.off ? LoopMode.infinite : preferred,
        count: _settings.state.loopCount,
      );
      final save = _persistLoop();
      await operation;
      await save;
    }
    await _engine.startLoop();
  }

  /// 暂停循环时保留选区；清除选区仍由时间轴上的清除按钮完成。
  Future<void> stopLoopKeepRegion() async {
    _cancelSentenceAdvance();
    _cancelCompare();
    final operation = _engine.setLoopMode(LoopMode.off);
    final save = _persistLoop();
    await operation;
    await save;
  }

  /// 退出精听，从媒体开头正常播放，保留已经框选的 A/B 边界。
  Future<void> exitPrecisionAndRestart() async {
    if (!_engine.snapshot.hasMedia) return;
    await stopLoopKeepRegion();
    await _engine.seekTo(0);
    await _engine.play();
    await _persistProgress();
  }

  /// 单句循环（需求 §3.2-7）：把该句设为 AB 片段并立即开始循环。
  Future<void> loopCue(SubtitleCue cue) async {
    _cancelSentenceAdvance();
    final operation = _engine.setLoopRegion(
      cue.startMs,
      cue.endMs,
      mode: LoopMode.infinite,
    );
    final save = _persistLoop();
    await operation;
    await _settings.setLoopMode(LoopMode.infinite);
    await save;
    await _engine.startLoop();
  }

  /// 精听模式下点句即循环。开启自动推进时，当前句按设置遍数播放后进入下一句。
  Future<void> loopSentence(
    SubtitleCue cue, {
    required List<SubtitleCue> playlist,
    required bool autoAdvance,
  }) async {
    _sentencePlaylist = playlist;
    _sentenceIndex = playlist.indexWhere(
      (item) => item.startMs == cue.startMs && item.endMs == cue.endMs,
    );
    _autoAdvanceCurrent = autoAdvance && _sentenceIndex >= 0;
    final count = _settings.state.loopCount.clamp(1, 20).toInt();
    final mode =
        _autoAdvanceCurrent || _settings.state.loopMode == LoopMode.count
        ? LoopMode.count
        : LoopMode.infinite;
    final operation = _engine.setLoopRegion(
      cue.startMs,
      cue.endMs,
      mode: mode,
      count: mode == LoopMode.count ? count : null,
    );
    final save = _persistLoop();
    await operation;
    await save;
    await _engine.startLoop();
  }

  void _handleSentenceLoopFinished() {
    if (!_autoAdvanceCurrent || _sentenceIndex < 0) return;
    if (!_settings.state.autoAdvanceSentences) {
      _cancelSentenceAdvance();
      return;
    }
    final nextIndex = nextSentenceIndex(
      _sentenceIndex,
      _sentencePlaylist.length,
      repeat: _settings.state.repeatSentenceList,
    );
    if (nextIndex == null) {
      _autoAdvanceCurrent = false;
      return;
    }

    final nextCue = _sentencePlaylist[nextIndex];
    final count = _settings.state.loopCount.clamp(1, 20).toInt();
    _sentenceIndex = nextIndex;
    Future<void>.delayed(Duration.zero, () async {
      if (!_autoAdvanceCurrent) return;
      final operation = _engine.setLoopRegion(
        nextCue.startMs,
        nextCue.endMs,
        mode: LoopMode.count,
        count: count,
      );
      final save = _persistLoop();
      await operation;
      await save;
      if (_autoAdvanceCurrent) await _engine.startLoop();
    });
  }

  void _cancelSentenceAdvance() {
    _autoAdvanceCurrent = false;
    _sentencePlaylist = const [];
    _sentenceIndex = -1;
  }

  /// A changed sentence invalidates the cached sequential playlist.
  Future<void> sentenceChanged({
    required int startMs,
    required int endMs,
  }) async {
    _cancelSentenceAdvance();
    final region = _engine.snapshot.loopRegion;
    if (region != null && region.startMs == startMs && region.endMs == endMs) {
      await stopLoopKeepRegion();
    }
  }

  /// 跳到某句并从头听（不改变循环区间）。
  Future<void> jumpToCue(SubtitleCue cue) async {
    _cancelSentenceAdvance();
    _cancelCompare();
    await _engine.seekTo(cue.startMs);
    if (!state.isPlaying) {
      await _engine.play();
    }
  }

  Future<void> _persistLoop() {
    final snapshot = _engine.snapshot;
    final id = snapshot.mediaId;
    final region = snapshot.loopRegion;
    if (id == null || id != _currentMediaId) return Future<void>.value();
    // Serialize saves so rapid drags cannot finish out of order. Capture the
    // engine snapshot now, before any asynchronous seek or player shutdown.
    final write = _loopWrites.catchError((_) {}).then((_) async {
      if (region == null) {
        await _mediaDao.clearLoopRegion(id);
      } else {
        await _mediaDao.updateLoopRegion(
          id,
          startMs: region.startMs,
          endMs: region.endMs,
          mode: snapshot.loopMode,
          count: snapshot.loopCount,
        );
      }
    });
    _loopWrites = write;
    return write;
  }

  // ------------------------------------------------------------------
  // 录音对比（需求 §3.3-9）
  // ------------------------------------------------------------------

  /// 先播原声片段，紧接着播自己的录音，形成对比。
  Future<String> compareWithRecording() async {
    final clip = _recorder.lastClip;
    final region = state.loopRegion;
    if (clip == null) return '还没有录音，先开启「跟读停顿」录一段吧';
    if (region == null) return '先选一段 AB 片段才能做对比';

    _cancelCompare();
    await _engine.seekTo(region.startMs);
    await _engine.play();

    // 原声这一段实际要播多久（考虑倍速），留 250ms 缓冲再切录音
    final realMs =
        DurationUtils.realDurationMs(region.lengthMs, state.speed) + 250;
    _compareTimer = Timer(Duration(milliseconds: realMs), () async {
      await _engine.pause();
      final path = _recorder.lastClip?.path;
      if (path == null) return;
      await _recorder.playClip(path);
    });
    return '正在对比播放：先原声，后录音';
  }

  Future<void> stopRecordingPlayback() => _recorder.stopClip();

  /// 删除录音（需求：录音文件可一键删除，不做长期保存）。
  Future<void> deleteRecording() async {
    _cancelCompare();
    await _recorder.clearAll();
  }

  void _cancelCompare() {
    _compareTimer?.cancel();
    _compareTimer = null;
    _recorder.stopClip();
  }

  // ------------------------------------------------------------------
  // 通知栏同步 & 进度持久化
  // ------------------------------------------------------------------

  void _syncTicker() {
    if (state.isPlaying || state.status == PlaybackStatus.gapCounting) {
      _ticker ??= Timer.periodic(const Duration(seconds: 2), (_) => _onTick());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _onTick() async {
    _tickCount++;
    await _syncNotification(force: true);
    if (_tickCount % 3 == 0) {
      await _persistProgress();
    }
  }

  Future<void> _syncNotification({bool force = false}) async {
    final name = _currentName;
    if (name == null) return;

    final key =
        '${state.mediaId}|${state.isPlaying}|${state.speed}|'
        '${_progressText(state)}';
    if (!force && key == _lastNotificationKey) return;
    _lastNotificationKey = key;

    await _background.update(
      title: name,
      text: _progressText(state),
      playing: state.isPlaying,
      speed: state.speed,
      positionMs: state.positionMs,
      durationMs: state.durationMs,
      keepAwake: state.isPlaying || state.status == PlaybackStatus.gapCounting,
    );
  }

  String _progressText(PlaybackSnapshot snapshot) {
    if (state.status == PlaybackStatus.gapCounting &&
        snapshot.gapRemaining != null) {
      return '跟读中 ${snapshot.gapRemaining}…';
    }
    if (state.status == PlaybackStatus.loopFinished) {
      return '循环完成 · ${snapshot.loopButtonLabel}';
    }
    return '${DurationUtils.formatClock(snapshot.positionMs)} / '
        '${DurationUtils.formatClock(snapshot.durationMs)}';
  }

  Future<void> _persistProgress() async {
    if (_leaving) return;
    final snapshot = _engine.snapshot;
    final id = snapshot.mediaId;
    if (id == null) return;
    final position = snapshot.positionMs;
    final duration = snapshot.durationMs;
    // 播完的文件把进度归零，下次进入从头开始（需求 §4.2：不做自动循环整文件）
    final savedPosition = (duration > 0 && position >= duration - 1200)
        ? 0
        : position;
    await _writeProgress(id, savedPosition);
  }

  Future<void> _writeProgress(int id, int positionMs) {
    final write = _progressWrites
        .catchError((_) {})
        .then(
          (_) => _mediaDao.updateProgress(
            id,
            positionMs: positionMs,
            lastPlayedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    _progressWrites = write;
    return write;
  }

  /// 暴露给界面：把当前进度落盘（例如 App 退到后台时）。
  Future<void> flushProgress() => _persistProgress();

  @override
  void dispose() {
    _compareTimer?.cancel();
    _ticker?.cancel();
    _engine.onLoopFinished = null;
    _engineSubscription?.cancel();
    super.dispose();
  }
}

final playbackProvider =
    StateNotifierProvider<PlaybackNotifier, PlaybackSnapshot>((ref) {
      return PlaybackNotifier(
        engine: ref.watch(playbackEngineProvider),
        mediaDao: ref.watch(mediaDaoProvider),
        settings: ref.watch(settingsProvider.notifier),
        background: ref.watch(backgroundPlaybackServiceProvider),
        recorder: ref.watch(recordingServiceProvider),
        readMediaPlaybackMode: () => ref.read(mediaPlaybackModeProvider),
      );
    });

/// 主题模式交给 UI 层从设置映射（数据层不依赖 material）。
final settingsSnapshotProvider = Provider<AppSettings>(
  (ref) => ref.watch(settingsProvider),
);

/// 最近一条录音（跟读对比用）。
/// 录音是原生能力，完成时机由原生回调决定，所以用流把它暴露成响应式状态。
final recordedClipProvider = StreamProvider<RecordedClip?>((ref) {
  return ref.watch(recordingServiceProvider).clipStream;
});
