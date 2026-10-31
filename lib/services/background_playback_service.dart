import 'native_channel.dart';

/// 后台播放 / 锁屏控制的桥接服务。
///
/// 只负责把「现在在播什么、播到哪、什么速度」同步给原生前台服务，
/// 以及把通知栏上的操作回传上来；播放本身不在原生侧做（见 PlaybackService.kt 的说明）。
class BackgroundPlaybackService {
  BackgroundPlaybackService(this._channel) {
    _channel.notificationActions.listen(_dispatch);
  }

  final NativeChannel _channel;

  void Function(String action)? onToggle;
  void Function()? onPrevious;
  void Function()? onNext;
  void Function()? onSpeedCycle;
  void Function()? onPlay;
  void Function()? onPause;
  void Function(int positionMs)? onSeek;

  bool _serviceStarted = false;

  void _dispatch(String action) {
    if (action.startsWith('seek:')) {
      final position = int.tryParse(action.substring(5));
      if (position != null) onSeek?.call(position);
      return;
    }
    switch (action) {
      case 'play':
        onPlay?.call();
        break;
      case 'pause':
        onPause?.call();
        break;
      case 'toggle':
        onToggle?.call('toggle');
        break;
      case 'prev':
        onPrevious?.call();
        break;
      case 'next':
        onNext?.call();
        break;
      case 'speed':
        onSpeedCycle?.call();
        break;
    }
  }

  /// 开始播放时调用，拉起前台服务（必须在应用处于前台时调用，符合 Android 12+ 限制）。
  Future<void> start({
    required String title,
    required String text,
    required bool playing,
    required double speed,
    required int positionMs,
    required int durationMs,
    required bool keepAwake,
  }) async {
    final ok = await _channel.startForegroundPlayback(
      title: title,
      text: text,
      playing: playing,
      speed: speed,
      positionMs: positionMs,
      durationMs: durationMs,
      keepAwake: keepAwake,
    );
    _serviceStarted = ok;
  }

  /// 播放状态变化时刷新通知内容。
  Future<void> update({
    required String title,
    required String text,
    required bool playing,
    required double speed,
    required int positionMs,
    required int durationMs,
    required bool keepAwake,
  }) async {
    if (!_serviceStarted) {
      await start(
        title: title,
        text: text,
        playing: playing,
        speed: speed,
        positionMs: positionMs,
        durationMs: durationMs,
        keepAwake: keepAwake,
      );
      return;
    }
    await _channel.updatePlaybackNotification(
      title: title,
      text: text,
      playing: playing,
      speed: speed,
      positionMs: positionMs,
      durationMs: durationMs,
      keepAwake: keepAwake,
    );
  }

  /// 退出播放页时撤掉前台服务与通知。
  Future<void> stop() async {
    if (!_serviceStarted) return;
    _serviceStarted = false;
    await _channel.stopForegroundPlayback();
  }
}
