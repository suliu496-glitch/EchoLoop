/// 时间相关的格式化与换算工具。
///
/// 项目内部统一用**毫秒 int** 存储时间点，避免 Duration 在数据库与 JSON 之间
/// 反复转换带来的精度损失；只在展示层调用这里的函数转成字符串。
class DurationUtils {
  DurationUtils._();

  /// 播放器主时钟：`mm:ss.d`，超过一小时自动补上小时段。
  /// 需求 §3.1-4 要求时间精确到 0.1 秒，所以只保留一位小数。
  static String formatClock(int milliseconds) {
    final ms = milliseconds < 0 ? 0 : milliseconds;
    final totalTenths = ms ~/ 100;
    final tenths = totalTenths % 10;
    final totalSeconds = totalTenths ~/ 10;
    final seconds = totalSeconds % 60;
    final totalMinutes = totalSeconds ~/ 60;
    final minutes = totalMinutes % 60;
    final hours = totalMinutes ~/ 60;

    final buffer = StringBuffer();
    if (hours > 0) {
      buffer.write(hours.toString().padLeft(2, '0'));
      buffer.write(':');
    }
    buffer.write(minutes.toString().padLeft(2, '0'));
    buffer.write(':');
    buffer.write(seconds.toString().padLeft(2, '0'));
    buffer.write('.');
    buffer.write(tenths);
    return buffer.toString();
  }

  /// 列表/卡片上的时长：`12:34`，超过一小时为 `1:02:03`。
  static String formatShort(int milliseconds) {
    final totalSeconds = (milliseconds < 0 ? 0 : milliseconds) ~/ 1000;
    final seconds = totalSeconds % 60;
    final totalMinutes = totalSeconds ~/ 60;
    final minutes = totalMinutes % 60;
    final hours = totalMinutes ~/ 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  /// 字幕编辑器用的毫秒级时间戳：`00:00:01.250`。
  static String formatMilliseconds(int milliseconds, {String separator = '.'}) {
    final ms = milliseconds < 0 ? 0 : milliseconds;
    final millis = ms % 1000;
    final totalSeconds = ms ~/ 1000;
    final seconds = totalSeconds % 60;
    final totalMinutes = totalSeconds ~/ 60;
    final minutes = totalMinutes % 60;
    final hours = totalMinutes ~/ 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}$separator'
        '${millis.toString().padLeft(3, '0')}';
  }

  /// 把「秒」转毫秒，用于倍速、拖动等浮点场景。
  static int secondsToMs(double seconds) => (seconds * 1000).round();

  /// 毫秒转秒（浮点）。
  static double msToSeconds(int milliseconds) => milliseconds / 1000.0;

  /// 倍速下这段音频实际要花多少真实时间（毫秒）。
  ///
  /// 循环边界计时器靠它算「还要等多久才到 B 点」，
  /// 0.5 倍速时同样的音频要花两倍真实时间，这里必须换算，否则循环会提前触发。
  static int realDurationMs(int audioMs, double speed) {
    if (speed <= 0) return audioMs;
    return (audioMs / speed).round();
  }
}
