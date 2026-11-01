import 'dart:async';
import 'package:echoloop/data/dao/media_dao.dart';
import 'package:echoloop/data/models/app_settings.dart';
import 'package:echoloop/data/models/media_item.dart';
import 'package:echoloop/domain/playback/playback_engine.dart';
import 'package:echoloop/domain/playback/playback_state.dart';
import 'package:echoloop/providers/playback_provider.dart';
import 'package:echoloop/providers/settings_provider.dart';
import 'package:echoloop/services/background_playback_service.dart';
import 'package:echoloop/services/recording_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Engine extends Fake implements PlaybackEngine {
  final events = StreamController<PlaybackSnapshot>.broadcast();
  @override
  Stream<PlaybackSnapshot> get snapshots => events.stream;
  @override
  PlaybackSnapshot snapshot = const PlaybackSnapshot();
  @override
  void Function()? onLoopFinished;
  @override
  void Function(int)? onGapStart;
  @override
  void Function()? onGapEnd;
  @override
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
    double speed = 1,
  }) async {
    snapshot = PlaybackSnapshot(
      mediaId: mediaId,
      mediaName: name,
      mediaUri: uri,
      isVideo: isVideo,
      positionMs: startPositionMs,
      loopRegion: loopRegion,
      loopMode: loopMode,
      loopCount: loopCount,
    );
    // Intentionally withhold stream notifications to reproduce a lagging UI state.
  }

  @override
  Future<void> setLoopRegion(
    int startMs,
    int endMs, {
    LoopMode? mode,
    int? count,
  }) async {
    snapshot = snapshot.copyWith(
      loopRegion: LoopRegion(startMs: startMs, endMs: endMs),
      loopMode: mode ?? LoopMode.infinite,
      loopCount: count ?? snapshot.loopCount,
    );
  }

  @override
  Future<void> setLoopMode(LoopMode mode, {int? count}) async {
    snapshot = snapshot.copyWith(
      loopMode: mode,
      loopCount: count ?? snapshot.loopCount,
    );
  }

  @override
  Future<void> startLoop() async {}
  @override
  Future<void> close() async {
    snapshot = const PlaybackSnapshot();
  }
}

class _Dao extends Fake implements MediaDao {
  final items = <int, MediaItem>{};
  Completer<void>? nextWriteGate;
  @override
  Future<MediaItem?> findById(int id) async => items[id];
  @override
  Future<void> updateLoopRegion(
    int id, {
    int? startMs,
    int? endMs,
    required LoopMode mode,
    required int count,
  }) async {
    final gate = nextWriteGate;
    nextWriteGate = null;
    if (gate != null) await gate.future;
    items[id] = items[id]!.copyWith(
      loopStartMs: startMs,
      loopEndMs: endMs,
      loopMode: mode,
      loopCount: count,
    );
  }

  @override
  Future<void> clearLoopRegion(int id) async {
    items[id] = items[id]!.copyWith(
      clearLoopRegion: true,
      loopMode: LoopMode.off,
    );
  }

  @override
  Future<void> updateProgress(
    int id, {
    required int positionMs,
    required int lastPlayedAt,
  }) async {
    items[id] = items[id]!.copyWith(
      positionMs: positionMs,
      lastPlayedAt: lastPlayedAt,
    );
  }
}

class _Settings extends Fake implements SettingsNotifier {
  @override
  AppSettings state = const AppSettings();
  @override
  Future<void> setLastMediaId(int? id) async {}
}

class _Background extends Fake implements BackgroundPlaybackService {
  @override
  void Function(String)? onToggle;
  @override
  void Function()? onPrevious;
  @override
  void Function()? onNext;
  @override
  void Function()? onSpeedCycle;
  @override
  void Function()? onPlay;
  @override
  void Function()? onPause;
  @override
  void Function(int)? onSeek;
  @override
  Future<void> start({
    required String title,
    required String text,
    required bool playing,
    required double speed,
    required int positionMs,
    required int durationMs,
    required bool keepAwake,
  }) async {}
  @override
  Future<void> stop() async {}
}

class _Recorder extends Fake implements RecordingService {
  @override
  Future<void> stopClip() async {}
  @override
  Future<void> cancel() async {}
}

void main() {
  test('选区在异步状态落后、切换媒体和重开后仍能恢复', () async {
    final dao = _Dao();
    final engine = _Engine();
    final first = MediaItem(
      id: 1,
      uri: 'one',
      name: 'one',
      kind: MediaKind.video,
      createdAt: 1,
    );
    final second = MediaItem(
      id: 2,
      uri: 'two',
      name: 'two',
      kind: MediaKind.video,
      createdAt: 2,
    );
    dao.items.addAll({1: first, 2: second});
    final notifier = PlaybackNotifier(
      engine: engine,
      mediaDao: dao,
      settings: _Settings(),
      background: _Background(),
      recorder: _Recorder(),
      readMediaPlaybackMode: () => MediaPlaybackMode.sequential,
    );
    await notifier.openMedia(first, queue: [first, second], autoPlay: false);
    await notifier.setLoopRegion(1200, 4500);
    expect(dao.items[1]!.loopStartMs, 1200);
    expect(dao.items[1]!.loopEndMs, 4500);
    await notifier.nextMedia();
    await notifier.previousMedia();
    expect(
      engine.snapshot.loopRegion,
      const LoopRegion(startMs: 1200, endMs: 4500),
    );
    await notifier.stopLoopKeepRegion();
    expect(dao.items[1]!.loopMode, LoopMode.off);
    expect(dao.items[1]!.loopStartMs, 1200);
    await notifier.startLoop();
    expect(dao.items[1]!.loopMode, LoopMode.infinite);
    await notifier.leavePlayer();
    await notifier.openMedia(first, autoPlay: false);
    expect(
      engine.snapshot.loopRegion,
      const LoopRegion(startMs: 1200, endMs: 4500),
    );
    notifier.dispose();
    await engine.events.close();
  });

  test('连续框选后立即退出仍按顺序保存最后选区', () async {
    final dao = _Dao();
    final engine = _Engine();
    final item = MediaItem(
      id: 1,
      uri: 'one',
      name: 'one',
      kind: MediaKind.video,
      createdAt: 1,
    );
    dao.items[1] = item;
    final notifier = PlaybackNotifier(
      engine: engine,
      mediaDao: dao,
      settings: _Settings(),
      background: _Background(),
      recorder: _Recorder(),
      readMediaPlaybackMode: () => MediaPlaybackMode.sequential,
    );
    await notifier.openMedia(item, autoPlay: false);
    final gate = Completer<void>();
    dao.nextWriteGate = gate;
    final first = notifier.setLoopRegion(1000, 2000);
    await Future<void>.delayed(Duration.zero);
    final second = notifier.setLoopRegion(3000, 5000);
    final closing = notifier.leavePlayer();
    gate.complete();
    await Future.wait([first, second, closing]);
    expect(dao.items[1]!.loopStartMs, 3000);
    expect(dao.items[1]!.loopEndMs, 5000);
    await notifier.openMedia(item, autoPlay: false);
    expect(
      engine.snapshot.loopRegion,
      const LoopRegion(startMs: 3000, endMs: 5000),
    );
    notifier.dispose();
    await engine.events.close();
  });
}
