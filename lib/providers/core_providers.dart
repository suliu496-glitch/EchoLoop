import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dao/loop_preset_dao.dart';
import '../data/dao/media_dao.dart';
import '../data/dao/settings_dao.dart';
import '../data/dao/subtitle_dao.dart';
import '../data/db/database_helper.dart';
import '../domain/playback/playback_engine.dart';
import '../services/app_directories.dart';
import '../services/background_playback_service.dart';
import '../services/media_import_service.dart';
import '../services/media_source_resolver.dart';
import '../services/native_channel.dart';
import '../services/recording_service.dart';
import '../services/subtitle_service.dart';
import '../services/thumbnail_service.dart';

/// 依赖注入总表。
///
/// 分三层：基础资源（数据库 / 原生通道 / 目录）→ 仓储（DAO）→ 服务。
/// UI 只依赖 provider，不直接 new 任何服务，方便替换实现与写测试。

// ---------------------------------------------------------------------------
// 基础资源
// ---------------------------------------------------------------------------

final databaseHelperProvider = Provider<DatabaseHelper>(
  (ref) => DatabaseHelper.instance,
);

final nativeChannelProvider = Provider<NativeChannel>((ref) {
  final channel = NativeChannel();
  ref.onDispose(channel.dispose);
  return channel;
});

final appDirectoriesProvider = Provider<AppDirectories>((ref) => AppDirectories());

// ---------------------------------------------------------------------------
// 仓储
// ---------------------------------------------------------------------------

final mediaDaoProvider = Provider<MediaDao>(
  (ref) => MediaDao(ref.watch(databaseHelperProvider)),
);

final subtitleDaoProvider = Provider<SubtitleDao>(
  (ref) => SubtitleDao(ref.watch(databaseHelperProvider)),
);

final loopPresetDaoProvider = Provider<LoopPresetDao>(
  (ref) => LoopPresetDao(ref.watch(databaseHelperProvider)),
);

final settingsDaoProvider = Provider<SettingsDao>(
  (ref) => SettingsDao(ref.watch(databaseHelperProvider)),
);

// ---------------------------------------------------------------------------
// 服务
// ---------------------------------------------------------------------------

final thumbnailServiceProvider = Provider<ThumbnailService>(
  (ref) => ThumbnailService(
    channel: ref.watch(nativeChannelProvider),
    directories: ref.watch(appDirectoriesProvider),
  ),
);

final mediaImportServiceProvider = Provider<MediaImportService>(
  (ref) => MediaImportService(
    channel: ref.watch(nativeChannelProvider),
    mediaDao: ref.watch(mediaDaoProvider),
    thumbnailService: ref.watch(thumbnailServiceProvider),
  ),
);

final subtitleServiceProvider = Provider<SubtitleService>(
  (ref) => SubtitleService(
    channel: ref.watch(nativeChannelProvider),
    dao: ref.watch(subtitleDaoProvider),
  ),
);

final recordingServiceProvider = Provider<RecordingService>((ref) {
  final service = RecordingService(
    channel: ref.watch(nativeChannelProvider),
    directories: ref.watch(appDirectoriesProvider),
  );
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final backgroundPlaybackServiceProvider = Provider<BackgroundPlaybackService>(
  (ref) => BackgroundPlaybackService(ref.watch(nativeChannelProvider)),
);

/// 播放引擎全局唯一：保证「同一时刻只有一个播放器状态源」（需求 §9.4）。
final playbackEngineProvider = Provider<PlaybackEngine>((ref) {
  final engine = PlaybackEngine(
    resolver: NativePlayableSourceResolver(ref.watch(nativeChannelProvider)),
  );
  ref.onDispose(() {
    engine.dispose();
  });
  return engine;
});
