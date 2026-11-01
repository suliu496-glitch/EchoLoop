import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dao/settings_dao.dart';
import '../data/models/app_settings.dart';
import '../data/models/media_item.dart' show LoopMode;
import '../domain/playback/playback_engine.dart';
import '../services/native_channel.dart';
import 'core_providers.dart';

/// 全局设置。
///
/// 写入策略：任何一次修改都「先改内存态 → 立即回写数据库 → 同步给播放引擎」，
/// 保证界面响应是即时的，同时不丢配置。
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier({
    required SettingsDao dao,
    required PlaybackEngine engine,
    required NativeChannel channel,
  }) : _dao = dao,
       _engine = engine,
       _channel = channel,
       super(const AppSettings()) {
    _load();
  }

  final SettingsDao _dao;
  final PlaybackEngine _engine;
  final NativeChannel _channel;

  bool _loaded = false;

  /// 设置是否已经从数据库读取完毕（首帧后可放心使用）
  bool get loaded => _loaded;

  Future<void> _load() async {
    try {
      final values = await _dao.loadAll();
      final hasApiKey = await _channel.hasTranscriberApiKey().catchError(
        (_) => false,
      );
      state = AppSettings.fromValues(
        values,
      ).copyWith(transcriberApiKeyConfigured: hasApiKey);
    } catch (_) {
      // 读设置失败不应该拦住应用启动，用默认值继续
      state = const AppSettings();
    }
    _loaded = true;
    // 把关键项同步给引擎，避免「设置里是 0.75 倍速，实际播的是 1.0」
    await _engine.setGapSeconds(state.gapSeconds);
    _engine.setSpeed(state.speed);
  }

  Future<void> _persist() async {
    await _dao.putAll(state.toValues());
  }

  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _engine.setSpeed(speed);
    await _persist();
  }

  Future<void> setGapSeconds(int seconds) async {
    state = state.copyWith(gapSeconds: seconds);
    await _engine.setGapSeconds(seconds);
    await _persist();
  }

  Future<void> setLoopMode(LoopMode mode) async {
    state = state.copyWith(loopMode: mode);
    await _persist();
  }

  Future<void> setLoopCount(int count) async {
    state = state.copyWith(loopCount: count);
    await _persist();
  }

  Future<void> setSnapToSubtitle(bool enabled) async {
    state = state.copyWith(snapToSubtitle: enabled);
    await _persist();
  }

  Future<void> setSubtitleVisible(bool visible) async {
    state = state.copyWith(subtitleVisible: visible);
    await _persist();
  }

  Future<void> setTranscriberEndpoint(String endpoint) async {
    state = state.copyWith(transcriberEndpoint: endpoint.trim());
    await _persist();
  }

  Future<void> setTranscriberModel(String model) async {
    state = state.copyWith(transcriberModel: model.trim());
    await _persist();
  }

  Future<void> setTranscriberLanguage(String language) async {
    state = state.copyWith(transcriberLanguage: language.trim());
    await _persist();
  }

  Future<void> setAutoAdvanceSentences(bool enabled) async {
    state = state.copyWith(autoAdvanceSentences: enabled);
    await _persist();
  }

  Future<void> setRepeatSentenceList(bool enabled) async {
    state = state.copyWith(repeatSentenceList: enabled);
    await _persist();
  }

  Future<void> saveTranscriberApiKey(String value) async {
    await _channel.saveTranscriberApiKey(value.trim());
    state = state.copyWith(transcriberApiKeyConfigured: true);
  }

  Future<void> clearTranscriberApiKey() async {
    await _channel.clearTranscriberApiKey();
    state = state.copyWith(transcriberApiKeyConfigured: false);
  }

  Future<void> setRecordDuringGap(bool enabled) async {
    state = state.copyWith(recordDuringGap: enabled);
    await _persist();
  }

  Future<void> setThemeMode(ThemeModeSetting mode) async {
    state = state.copyWith(themeMode: mode);
    await _persist();
  }

  /// 记住上次打开的媒体，冷启动时可以提示继续。
  Future<void> setLastMediaId(int? mediaId) async {
    state = state.copyWith(lastMediaId: mediaId);
    await _persist();
  }

  /// 把「跟读停顿 + 录音」两个开关合起来判断：停顿关闭时录音没有意义。
  bool get effectiveRecordDuringGap =>
      state.recordDuringGap && state.gapEnabled;
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  return SettingsNotifier(
    dao: ref.watch(settingsDaoProvider),
    engine: ref.watch(playbackEngineProvider),
    channel: ref.watch(nativeChannelProvider),
  );
});
