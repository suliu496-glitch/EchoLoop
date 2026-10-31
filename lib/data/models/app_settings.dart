import '../../core/constants/app_constants.dart';
import 'media_item.dart';

/// 设置项在 `settings` 表里的键名。
class SettingKeys {
  SettingKeys._();

  static const String speed = 'playback.speed';
  static const String gapSeconds = 'playback.gap_seconds';
  static const String loopMode = 'playback.loop_mode';
  static const String loopCount = 'playback.loop_count';
  static const String snapToSubtitle = 'subtitle.snap_to_boundary';
  static const String subtitleVisible = 'subtitle.visible';
  static const String transcriberEndpoint = 'transcriber.endpoint';
  static const String transcriberModel = 'transcriber.model';
  static const String transcriberLanguage = 'transcriber.language';
  static const String autoAdvanceSentences = 'study.auto_advance_sentences';
  static const String recordDuringGap = 'shadowing.record_during_gap';
  static const String themeMode = 'ui.theme_mode';
  static const String lastMediaId = 'library.last_media_id';
}

/// 应用级设置（全局，跨媒体文件保持）。
///
/// 与需求 §4.2 的对应关系：
/// - [speed] 是全局设置，切换文件后保持上次选择；
/// - [snapToSubtitle] 对应「片段边界自动吸附字幕」开关；
/// - 循环区间不在这里，它是单文件独立存储（见 [MediaItem.loopStartMs]）。
class AppSettings {
  const AppSettings({
    this.speed = AppConstants.defaultSpeed,
    this.gapSeconds = 0,
    this.loopMode = LoopMode.infinite,
    this.loopCount = 3,
    this.snapToSubtitle = true,
    this.subtitleVisible = true,
    this.transcriberEndpoint = 'https://api.openai.com/v1',
    this.transcriberModel = 'whisper-1',
    this.transcriberLanguage = '',
    this.autoAdvanceSentences = false,
    this.transcriberApiKeyConfigured = false,
    this.recordDuringGap = false,
    this.themeMode = ThemeModeSetting.system,
    this.lastMediaId,
  });

  final double speed;

  /// 跟读停顿秒数，0 = 关闭
  final int gapSeconds;

  /// 手动 AB 片段循环默认使用的模式
  final LoopMode loopMode;

  /// 指定遍数模式的默认遍数
  final int loopCount;

  /// 拖动 A/B 点时是否吸附到最近的字幕句边界
  final bool snapToSubtitle;

  /// 字幕列表是否显示
  final bool subtitleVisible;

  /// OpenAI Whisper-compatible API root. API key is stored separately in Android Keystore.
  final String transcriberEndpoint;

  final String transcriberModel;

  /// Empty string means provider auto-detection.
  final String transcriberLanguage;

  /// When enabled, sentence loops use the configured repeat count and advance automatically.
  final bool autoAdvanceSentences;

  /// Runtime-only status; the key itself is never written to the settings table.
  final bool transcriberApiKeyConfigured;

  /// 跟读停顿期间是否自动开麦录音
  final bool recordDuringGap;

  final ThemeModeSetting themeMode;

  /// 上次打开的媒体，用于冷启动回到播放页
  final int? lastMediaId;

  bool get gapEnabled => gapSeconds > 0;

  AppSettings copyWith({
    double? speed,
    int? gapSeconds,
    LoopMode? loopMode,
    int? loopCount,
    bool? snapToSubtitle,
    bool? subtitleVisible,
    String? transcriberEndpoint,
    String? transcriberModel,
    String? transcriberLanguage,
    bool? autoAdvanceSentences,
    bool? transcriberApiKeyConfigured,
    bool? recordDuringGap,
    ThemeModeSetting? themeMode,
    int? lastMediaId,
  }) {
    return AppSettings(
      speed: speed ?? this.speed,
      gapSeconds: gapSeconds ?? this.gapSeconds,
      loopMode: loopMode ?? this.loopMode,
      loopCount: loopCount ?? this.loopCount,
      snapToSubtitle: snapToSubtitle ?? this.snapToSubtitle,
      subtitleVisible: subtitleVisible ?? this.subtitleVisible,
      transcriberEndpoint: transcriberEndpoint ?? this.transcriberEndpoint,
      transcriberModel: transcriberModel ?? this.transcriberModel,
      transcriberLanguage: transcriberLanguage ?? this.transcriberLanguage,
      autoAdvanceSentences: autoAdvanceSentences ?? this.autoAdvanceSentences,
      transcriberApiKeyConfigured:
          transcriberApiKeyConfigured ?? this.transcriberApiKeyConfigured,
      recordDuringGap: recordDuringGap ?? this.recordDuringGap,
      themeMode: themeMode ?? this.themeMode,
      lastMediaId: lastMediaId ?? this.lastMediaId,
    );
  }

  /// 从 settings 表的键值对还原。缺项一律回退默认值，保证升级不崩。
  factory AppSettings.fromValues(Map<String, String> values) {
    return AppSettings(
      speed:
          double.tryParse(values[SettingKeys.speed] ?? '') ??
          AppConstants.defaultSpeed,
      gapSeconds: int.tryParse(values[SettingKeys.gapSeconds] ?? '') ?? 0,
      loopMode: LoopMode.fromWire(values[SettingKeys.loopMode]),
      loopCount: int.tryParse(values[SettingKeys.loopCount] ?? '') ?? 3,
      snapToSubtitle: _asBool(values[SettingKeys.snapToSubtitle], true),
      subtitleVisible: _asBool(values[SettingKeys.subtitleVisible], true),
      transcriberEndpoint:
          values[SettingKeys.transcriberEndpoint] ??
          'https://api.openai.com/v1',
      transcriberModel: values[SettingKeys.transcriberModel] ?? 'whisper-1',
      transcriberLanguage: values[SettingKeys.transcriberLanguage] ?? '',
      autoAdvanceSentences: _asBool(
        values[SettingKeys.autoAdvanceSentences],
        false,
      ),
      recordDuringGap: _asBool(values[SettingKeys.recordDuringGap], false),
      themeMode: ThemeModeSetting.fromWire(values[SettingKeys.themeMode]),
      lastMediaId: int.tryParse(values[SettingKeys.lastMediaId] ?? ''),
    );
  }

  Map<String, String> toValues() => {
    SettingKeys.speed: speed.toString(),
    SettingKeys.gapSeconds: gapSeconds.toString(),
    SettingKeys.loopMode: loopMode.wire,
    SettingKeys.loopCount: loopCount.toString(),
    SettingKeys.snapToSubtitle: snapToSubtitle ? '1' : '0',
    SettingKeys.subtitleVisible: subtitleVisible ? '1' : '0',
    SettingKeys.transcriberEndpoint: transcriberEndpoint,
    SettingKeys.transcriberModel: transcriberModel,
    SettingKeys.transcriberLanguage: transcriberLanguage,
    SettingKeys.autoAdvanceSentences: autoAdvanceSentences ? '1' : '0',
    SettingKeys.recordDuringGap: recordDuringGap ? '1' : '0',
    SettingKeys.themeMode: themeMode.wire,
    if (lastMediaId != null) SettingKeys.lastMediaId: lastMediaId.toString(),
  };

  static bool _asBool(String? raw, bool fallback) {
    if (raw == null) return fallback;
    return raw == '1' || raw.toLowerCase() == 'true';
  }
}

/// 主题模式。单独定义而不直接用 `ThemeMode`，
/// 是为了让数据层不依赖 Flutter 的 material 库。
enum ThemeModeSetting {
  system('system'),
  light('light'),
  dark('dark');

  const ThemeModeSetting(this.wire);

  final String wire;

  static ThemeModeSetting fromWire(String? value) => switch (value) {
    'light' => ThemeModeSetting.light,
    'dark' => ThemeModeSetting.dark,
    _ => ThemeModeSetting.system,
  };

  String get label => switch (this) {
    ThemeModeSetting.system => '跟随系统',
    ThemeModeSetting.light => '浅色',
    ThemeModeSetting.dark => '深色',
  };
}
