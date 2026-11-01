import 'dart:async';

import 'package:echoloop/domain/playback/playable_source_resolver.dart';
import 'package:echoloop/domain/playback/playback_engine.dart';
import 'package:echoloop/domain/playback/playback_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _Streams extends Fake implements PlayerStream {
  final bufferingEvents = StreamController<bool>.broadcast();
  final playingEvents = StreamController<bool>.broadcast();
  final completedEvents = StreamController<bool>.broadcast();
  final errorEvents = StreamController<String>.broadcast();
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<bool> get playing => playingEvents.stream;
  @override
  Stream<bool> get buffering => bufferingEvents.stream;
  @override
  Stream<bool> get completed => completedEvents.stream;
  @override
  Stream<String> get error => errorEvents.stream;

  Future<void> close() async {
    await bufferingEvents.close();
    await playingEvents.close();
    await completedEvents.close();
    await errorEvents.close();
  }
}

class _Player extends Fake implements Player {
  _Player(this.calls);
  final List<String> calls;
  bool failStop = false;
  final events = _Streams();
  @override
  PlayerStream get stream => events;
  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    calls.add('open');
  }

  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> stop() async {
    calls.add('stop');
    if (failStop) throw StateError('stop failed');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await events.close();
  }
}

class _Video extends Fake implements VideoController {}

class _Resolver extends Fake implements PlayableSourceResolver {
  _Resolver(this.calls);
  final List<String> calls;
  @override
  Future<String> resolve(String uri) async {
    calls.add('resolve:$uri');
    return '/$uri';
  }

  @override
  Future<void> release(String uri) async {
    calls.add('release:$uri');
  }
}

void main() {
  test('退出视频前停止播放，再释放文件句柄', () async {
    final calls = <String>[];
    final engine = PlaybackEngine(
      resolver: _Resolver(calls),
      player: _Player(calls),
      videoController: _Video(),
    );
    await engine.open(
      mediaId: 1,
      uri: 'first',
      name: '视频',
      isVideo: true,
      autoPlay: false,
    );
    calls.clear();
    await engine.close();
    expect(calls, ['stop', 'release:first']);
    await engine.dispose();
  });

  test('切换视频时先停止并释放旧文件，再打开新文件', () async {
    final calls = <String>[];
    final engine = PlaybackEngine(
      resolver: _Resolver(calls),
      player: _Player(calls),
      videoController: _Video(),
    );
    await engine.open(
      mediaId: 1,
      uri: 'first',
      name: '视频一',
      isVideo: true,
      autoPlay: false,
    );
    calls.clear();
    await engine.open(
      mediaId: 2,
      uri: 'second',
      name: '视频二',
      isVideo: true,
      autoPlay: false,
    );
    expect(calls, ['stop', 'release:first', 'resolve:second', 'open']);
    await engine.dispose();
  });

  test('停止播放器失败时仍然释放文件句柄', () async {
    final calls = <String>[];
    final player = _Player(calls);
    final engine = PlaybackEngine(
      resolver: _Resolver(calls),
      player: player,
      videoController: _Video(),
    );
    await engine.open(
      mediaId: 1,
      uri: 'first',
      name: '视频',
      isVideo: true,
      autoPlay: false,
    );
    calls.clear();
    player.failStop = true;
    await expectLater(engine.close(), throwsStateError);
    expect(calls, ['stop', 'release:first']);
    await engine.dispose();
  });

  test('播放出错后停止转圈，后续缓冲及播放事件不能掩盖错误', () async {
    final calls = <String>[];
    final player = _Player(calls);
    final engine = PlaybackEngine(
      resolver: _Resolver(calls),
      player: player,
      videoController: _Video(),
    );
    await engine.open(
      mediaId: 1,
      uri: 'first',
      name: '视频',
      isVideo: true,
      autoPlay: false,
    );
    player.events.bufferingEvents.add(true);
    await Future<void>.delayed(Duration.zero);
    expect(engine.snapshot.buffering, isTrue);
    player.events.errorEvents.add('permission denied');
    await Future<void>.delayed(Duration.zero);
    expect(engine.snapshot.buffering, isFalse);
    expect(engine.snapshot.errorMessage, contains('权限'));
    player.events.bufferingEvents.add(true);
    player.events.playingEvents.add(true);
    player.events.completedEvents.add(true);
    await Future<void>.delayed(Duration.zero);
    expect(engine.snapshot.buffering, isFalse);
    expect(engine.snapshot.errorMessage, contains('权限'));
    expect(engine.snapshot.status, PlaybackStatus.error);
    await engine.dispose();
  });
}
