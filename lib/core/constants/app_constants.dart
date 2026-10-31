/// 全局常量：集中存放业务规则里出现的所有「魔法数字」，避免散落在各层。
class AppConstants {
  AppConstants._();

  // ---------------- 应用信息 ----------------
  static const String appName = 'EchoLoop';
  static const String appSlogan = '片段循环，逐句跟读';

  // ---------------- 数据库 ----------------
  static const String databaseName = 'echoloop.db';
  static const int databaseVersion = 1;

  // ---------------- 支持的媒体格式（需求 §3.1） ----------------
  static const List<String> videoExtensions = [
    'mp4',
    'mkv',
    'avi',
    'mov',
    'flv',
    'webm',
  ];

  static const List<String> audioExtensions = [
    'mp3',
    'wav',
    'm4a',
    'aac',
    'flac',
    'ogg',
  ];

  static const List<String> subtitleExtensions = ['srt', 'ass', 'vtt'];

  // ---------------- 播放参数 ----------------
  /// 倍速档位（需求 §3.1-2）
  static const List<double> speedPresets = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  static const double defaultSpeed = 1.0;

  /// 快捷微调档位（秒），对应「后退 5 / 后退 2 / 前进 2 / 前进 5」
  static const List<double> jumpPresets = [-5, -2, 2, 5];

  /// A/B 点精调步长（秒）
  static const double nudgeStepSeconds = 0.1;

  /// 片段边界吸附字幕的阈值（秒），需求 §4.1
  static const double snapThresholdSeconds = 1.0;

  // ---------------- 循环与跟读 ----------------
  /// 指定遍数可选值（需求 §3.1-3）
  static const List<int> loopCountPresets = [1, 2, 3, 4];

  /// 跟读停顿档位（秒），0 表示关闭（需求 §3.3-8）
  static const List<int> gapPresets = [0, 1, 2, 3, 5];

  /// 循环边界触发容差：宁可多播几十毫秒，也不要把句子尾巴切掉
  static const int loopTriggerToleranceMs = 30;

  /// 循环边界的兜底轮询间隔。
  ///
  /// 20ms 是权衡结果：比它更粗会在边界处明显迟滞，更细则白白耗电。
  /// 真正保证精度的是 [PlaybackClock] 的高精度估算，轮询只负责兜底。
  static const Duration loopPollInterval = Duration(milliseconds: 20);

  /// 循环边界精确计时器的最小等待时长，避免等待过短导致计时器抖动
  static const int minLoopTimerMs = 5;

  /// 播放时钟允许的最大漂移：估算位置与内核回报位置差超过它就重新对齐。
  ///
  /// 太小会被内核抖动带着跑，太大会放任估算飘走。120ms 大约是人耳能分辨
  /// 口型与声音错位的下限。
  static const int clockMaxDriftMs = 120;

  // ---------------- 缩略图 ----------------
  static const int thumbnailMaxWidth = 480;
  static const int thumbnailQuality = 85;

  // ---------------- 目录名 ----------------
  static const String thumbnailDirName = 'thumbnails';
  static const String recordingDirName = 'recordings';
}
