import 'dart:async';

import 'package:flutter/services.dart';

import '../core/errors/app_exception.dart';

/// 原生侧的媒体条目（导入或扫描的结果）。
class NativeMediaEntry {
  const NativeMediaEntry({
    required this.uri,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.durationMs,
    required this.isVideo,
  });

  final String uri;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final int durationMs;
  final bool isVideo;

  factory NativeMediaEntry.fromMap(Map<Object?, Object?> map) {
    return NativeMediaEntry(
      uri: (map['uri'] as String?) ?? '',
      name: (map['name'] as String?) ?? '未命名',
      mimeType: (map['mimeType'] as String?) ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      isVideo: (map['isVideo'] as bool?) ?? false,
    );
  }
}

/// 选中的字幕文件。
class PickedSubtitleFile {
  const PickedSubtitleFile({
    required this.uri,
    required this.name,
    required this.content,
  });

  final String uri;
  final String name;
  final String content;
}

class TranscriptionAudioChunk {
  const TranscriptionAudioChunk({
    required this.path,
    required this.startMs,
    required this.durationMs,
  });

  final String path;
  final int startMs;
  final int durationMs;

  factory TranscriptionAudioChunk.fromMap(Map<Object?, Object?> map) {
    return TranscriptionAudioChunk(
      path: map['path'] as String? ?? '',
      startMs: (map['startMs'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 逻辑权限组。Flutter 侧只说「我要读视频」，具体申请哪些系统权限由原生按 API 版本决定。
enum NativePermissionGroup {
  mediaVideo('mediaVideo'),
  mediaAudio('mediaAudio'),
  microphone('microphone'),
  notification('notification');

  const NativePermissionGroup(this.wire);

  final String wire;

  String get label => switch (this) {
    NativePermissionGroup.mediaVideo => '读取视频',
    NativePermissionGroup.mediaAudio => '读取音频',
    NativePermissionGroup.microphone => '麦克风录音',
    NativePermissionGroup.notification => '通知（锁屏控制）',
  };
}

/// 与 Android 原生层通信的唯一入口。
///
/// 所有平台通道调用都收在这里，好处有两个：
/// 1. 上层（服务 / UI）拿到的永远是「成功结果或 [AppException]」，
///    不会到处写 `try { MethodChannel } catch (PlatformException)`（需求 §9.3）；
/// 2. 原生方法清单集中可见，方便对照 `NativeBridge.kt` 维护。
class NativeChannel {
  NativeChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const String channelName = 'com.echoloop/player';

  final MethodChannel _channel;

  final StreamController<String> _notificationActions =
      StreamController<String>.broadcast();

  /// 通知栏 / 锁屏上的操作（toggle / prev / next / speed）。
  Stream<String> get notificationActions => _notificationActions.stream;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onNotificationAction') {
      final arguments = call.arguments;
      if (arguments is Map && arguments['action'] is String) {
        _notificationActions.add(arguments['action'] as String);
      }
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _notificationActions.close();
  }

  // ------------------------------------------------------------------
  // 文件导入
  // ------------------------------------------------------------------

  Future<List<NativeMediaEntry>> pickMediaFiles({
    bool allowMultiple = true,
  }) async {
    final result = await _invoke<List<Object?>>(
      'pickMediaFiles',
      args: {'allowMultiple': allowMultiple},
      fallback: const [],
    );
    return _toEntries(result ?? const []);
  }

  Future<PickedSubtitleFile?> pickSubtitleFile() async {
    final result = await _invoke<Map<Object?, Object?>>('pickSubtitleFile');
    if (result == null) return null;
    return PickedSubtitleFile(
      uri: (result['uri'] as String?) ?? '',
      name: (result['name'] as String?) ?? '字幕',
      content: (result['content'] as String?) ?? '',
    );
  }

  Future<List<NativeMediaEntry>> scanMediaStore({
    String scope = 'all',
    String keyword = '',
  }) async {
    final result = await _invoke<List<Object?>>(
      'scanMediaStore',
      args: {'scope': scope, 'keyword': keyword},
      fallback: const [],
    );
    return _toEntries(result ?? const []);
  }

  // ------------------------------------------------------------------
  // 播放路径
  // ------------------------------------------------------------------

  /// 把 URI 解析成播放内核能读的路径，失败时抛 [PlaybackException]。
  Future<String> resolvePlayablePath(String uri) async {
    final result = await _invoke<Map<Object?, Object?>>(
      'resolvePlayablePath',
      args: {'uri': uri},
    );
    final path = result?['path'] as String?;
    if (path == null || path.isEmpty) {
      throw PlaybackException(
        (result?['message'] as String?) ?? '无法打开这个文件',
        code: (result?['mode'] as String?) ?? 'resolve_failed',
      );
    }
    return path;
  }

  Future<void> releasePlayablePath(String uri) =>
      _invoke<bool>('releasePlayablePath', args: {'uri': uri}, fallback: false);

  Future<void> releaseAllPlayablePaths() =>
      _invoke<bool>('releaseAllPlayablePaths', fallback: false);

  /// Extracts/remuxes the source audio into bounded AAC/M4A chunks for transcription.
  Future<List<TranscriptionAudioChunk>> exportTranscriptionAudio(
    String uri,
  ) async {
    final result = await _invoke<List<Object?>>(
      'exportTranscriptionAudio',
      args: {'uri': uri},
      fallback: const [],
    );
    return [
      for (final item in result ?? const [])
        if (item is Map)
          TranscriptionAudioChunk.fromMap(item.cast<Object?, Object?>()),
    ];
  }

  Future<void> deleteTranscriptionAudio(List<String> paths) => _invoke<bool>(
    'deleteTranscriptionAudio',
    args: {'paths': paths},
    fallback: false,
  );

  Future<bool> hasTranscriberApiKey() async =>
      (await _invoke<bool>('hasTranscriberApiKey', fallback: false)) ?? false;

  Future<String?> readTranscriberApiKey() =>
      _invoke<String>('readTranscriberApiKey');

  Future<void> saveTranscriberApiKey(String value) => _invoke<bool>(
    'saveTranscriberApiKey',
    args: {'value': value},
    fallback: false,
  );

  Future<void> clearTranscriberApiKey() =>
      _invoke<bool>('clearTranscriberApiKey', fallback: false);

  // ------------------------------------------------------------------
  // 缩略图 / 文本
  // ------------------------------------------------------------------

  Future<String?> createThumbnail({
    required String uri,
    required String outPath,
    int timeMs = -1,
    int maxWidth = 480,
  }) {
    return _invoke<String>(
      'createThumbnail',
      args: {
        'uri': uri,
        'timeMs': timeMs,
        'outPath': outPath,
        'maxWidth': maxWidth,
      },
    );
  }

  Future<String> readTextFile(String uri) async {
    final text = await _invoke<String>('readTextFile', args: {'uri': uri});
    if (text == null) {
      throw const SubtitleException('文件读取失败或内容为空', code: 'read_failed');
    }
    return text;
  }

  // ------------------------------------------------------------------
  // 权限
  // ------------------------------------------------------------------

  Future<Map<String, bool>> checkPermissions(
    List<NativePermissionGroup> groups,
  ) async {
    if (groups.isEmpty) return const {};
    final result = await _invoke<Map<Object?, Object?>>(
      'checkPermissions',
      args: {
        'groups': [for (final group in groups) group.wire],
      },
      fallback: const {},
    );
    return _toBoolMap(result ?? const {});
  }

  Future<Map<String, bool>> requestPermissions(
    List<NativePermissionGroup> groups,
  ) async {
    if (groups.isEmpty) return const {};
    final result = await _invoke<Map<Object?, Object?>>(
      'requestPermissions',
      args: {
        'groups': [for (final group in groups) group.wire],
      },
      fallback: const {},
    );
    return _toBoolMap(result ?? const {});
  }

  // ------------------------------------------------------------------
  // 录音
  // ------------------------------------------------------------------

  /// 返回 null 表示成功，否则是可读的错误信息。
  Future<String?> startRecording(String outPath) =>
      _invoke<String>('startRecording', args: {'outPath': outPath});

  /// 返回 { path, durationMs } 或 { error }。
  Future<Map<Object?, Object?>> stopRecording() async =>
      (await _invoke<Map<Object?, Object?>>(
        'stopRecording',
        fallback: const {},
      )) ??
      const {};

  Future<void> cancelRecording() =>
      _invoke<bool>('cancelRecording', fallback: false);

  // ------------------------------------------------------------------
  // 前台服务 / 通知
  // ------------------------------------------------------------------

  Future<bool> startForegroundPlayback({
    required String title,
    required String text,
    required bool playing,
    required double speed,
    required int positionMs,
    required int durationMs,
    required bool keepAwake,
  }) async {
    final result = await _invoke<bool>(
      'startForegroundPlayback',
      args: _notificationArgs(
        title,
        text,
        playing,
        speed,
        positionMs,
        durationMs,
        keepAwake,
      ),
      fallback: false,
    );
    return result ?? false;
  }

  Future<bool> updatePlaybackNotification({
    required String title,
    required String text,
    required bool playing,
    required double speed,
    required int positionMs,
    required int durationMs,
    required bool keepAwake,
  }) async {
    final result = await _invoke<bool>(
      'updatePlaybackNotification',
      args: _notificationArgs(
        title,
        text,
        playing,
        speed,
        positionMs,
        durationMs,
        keepAwake,
      ),
      fallback: false,
    );
    return result ?? false;
  }

  Future<bool> stopForegroundPlayback() async =>
      (await _invoke<bool>('stopForegroundPlayback', fallback: false)) ?? false;

  Future<bool> openAppNotificationSettings() async =>
      (await _invoke<bool>('openAppNotificationSettings', fallback: false)) ??
      false;

  Map<String, Object?> _notificationArgs(
    String title,
    String text,
    bool playing,
    double speed,
    int positionMs,
    int durationMs,
    bool keepAwake,
  ) => {
    'title': title,
    'text': text,
    'playing': playing,
    'speed': speed,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'keepAwake': keepAwake,
  };

  // ------------------------------------------------------------------
  // 内部工具
  // ------------------------------------------------------------------

  /// 统一封装：把 PlatformException 转成 [AppException]，统一错误出口。
  Future<T?> _invoke<T>(
    String method, {
    Map<String, Object?>? args,
    T? fallback,
  }) async {
    try {
      final result = await _channel.invokeMethod<T>(method, args);
      return result ?? fallback;
    } on MissingPluginException {
      throw AppException(
        '当前运行环境不支持该功能（原生通道不可用）',
        detail: 'method=$method',
        code: 'missing_plugin',
      );
    } on PlatformException catch (error) {
      throw AppException(
        error.message ?? '系统调用失败',
        detail: '${error.code} · method=$method',
        code: error.code,
      );
    }
  }

  List<NativeMediaEntry> _toEntries(List<Object?> raw) {
    return [
      for (final item in raw)
        if (item is Map)
          NativeMediaEntry.fromMap(item.cast<Object?, Object?>()),
    ];
  }

  Map<String, bool> _toBoolMap(Map<Object?, Object?> raw) {
    return {
      for (final entry in raw.entries)
        if (entry.key is String) entry.key! as String: entry.value == true,
    };
  }
}
