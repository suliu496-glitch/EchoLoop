import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'app_directories.dart';
import 'native_channel.dart';

/// 一次录音的结果。
class RecordedClip {
  const RecordedClip({required this.path, required this.durationMs});

  final String path;
  final int durationMs;

  String get fileName => path.split(Platform.pathSeparator).last;
}

/// 录音对比服务（需求 §3.3-9）。
///
/// 三条产品约束都落在这里：
/// - 录音只写到应用私有目录，随时可一键删除，不做长期保存；
/// - 只保留「本次跟读的最新一条」，避免缓存无限增长；
/// - 播放录音用独立的小播放器，不干扰主播放器的状态机
///   （对比播放时先播原声再播录音，主播放器需要保持位置不被打乱）。
class RecordingService {
  RecordingService({
    required NativeChannel channel,
    required AppDirectories directories,
  })  : _channel = channel,
        _directories = directories {
    _bindClipPlayer();
  }

  final NativeChannel _channel;
  final AppDirectories _directories;

  /// 录音结果的变化流，供 UI 响应式刷新「对比播放 / 删除录音」按钮状态。
  final StreamController<RecordedClip?> _clipController =
      StreamController<RecordedClip?>.broadcast();

  Stream<RecordedClip?> get clipStream => _clipController.stream;

  late final Player _clipPlayer = Player();
  StreamSubscription<bool>? _completedSubscription;

  bool _recording = false;
  String? _currentPath;
  RecordedClip? _lastClip;

  /// 最近一条录音
  RecordedClip? get lastClip => _lastClip;

  bool get isRecording => _recording;

  bool get hasClip => _lastClip != null;

  void _bindClipPlayer() {
    _completedSubscription = _clipPlayer.stream.completed.listen((completed) {
      if (completed) {
        _onClipCompleted?.call();
      }
    });
  }

  void Function()? _onClipCompleted;

  /// 开始录音。返回 null 表示成功，否则返回可读错误信息。
  Future<String?> start() async {
    if (_recording) return null;

    final granted = await _channel.requestPermissions([NativePermissionGroup.microphone]);
    if (granted[NativePermissionGroup.microphone.wire] != true) {
      // 优雅降级：不弹错、不崩溃，只告诉调用方这次录不了
      return '未获得麦克风权限，跟读录音已跳过';
    }

    // 每次录音前清掉上一条，保证「不做长期保存」
    await _deleteLastClip();

    final path = await _directories.newRecordingPath();
    final error = await _channel.startRecording(path);
    if (error != null) return error;

    _currentPath = path;
    _recording = true;
    return null;
  }

  /// 结束录音并保留结果。
  Future<RecordedClip?> stop() async {
    if (!_recording) return null;
    _recording = false;

    final result = await _channel.stopRecording();
    final path = result['path'] as String?;
    if (path == null || path.isEmpty) {
      _currentPath = null;
      return null;
    }
    final clip = RecordedClip(
      path: path,
      durationMs: (result['durationMs'] as num?)?.toInt() ?? 0,
    );
    _currentPath = null;
    _lastClip = clip;
    _emitClip();
    return clip;
  }

  /// 放弃当前录音（用户中途暂停 / 清选区时调用）。
  Future<void> cancel() async {
    if (!_recording) return;
    _recording = false;
    _currentPath = null;
    await _channel.cancelRecording();
  }

  /// 播放一段录音（对比跟读时先播原声、再播它）。
  Future<void> playClip(String path, {void Function()? onCompleted}) async {
    _onClipCompleted = onCompleted;
    final file = File(path);
    if (!await file.exists()) {
      _onClipCompleted = null;
      onCompleted?.call();
      return;
    }
    await _clipPlayer.open(Media(path), play: true);
  }

  Future<void> stopClip() async {
    _onClipCompleted = null;
    await _clipPlayer.stop();
  }

  /// 一键删除录音（需求 §3.3-9）。
  Future<void> clearAll() async {
    await stopClip();
    await _deleteLastClip();
    await _directories.clearRecordings();
  }

  Future<void> _deleteLastClip() async {
    final clip = _lastClip;
    _lastClip = null;
    if (clip != null) {
      await _directories.deleteQuietly(clip.path);
    }
    await _directories.deleteQuietly(_currentPath);
    _emitClip();
  }

  /// 把最新录音状态推给 UI（按钮的可用性依赖它）。
  void _emitClip() {
    if (!_clipController.isClosed) _clipController.add(_lastClip);
  }

  Future<void> dispose() async {
    await _completedSubscription?.cancel();
    await _clipPlayer.dispose();
    await _clipController.close();
  }
}
