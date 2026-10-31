import '../constants/app_constants.dart';

/// 文件名 / 体积相关的纯函数工具（不碰 IO，方便单测）。
class FileUtils {
  FileUtils._();

  /// 取小写扩展名，无扩展名返回空串。
  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// 去掉扩展名的显示名。
  static String stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return name;
    return name.substring(0, dot);
  }

  static bool isVideoName(String name) =>
      AppConstants.videoExtensions.contains(extensionOf(name));

  static bool isAudioName(String name) =>
      AppConstants.audioExtensions.contains(extensionOf(name));

  static bool isSubtitleName(String name) =>
      AppConstants.subtitleExtensions.contains(extensionOf(name));

  /// 人读体积：`1.2 GB`。
  static String humanSize(int bytes) {
    if (bytes <= 0) return '未知大小';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final text = value >= 100 || unitIndex == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text ${units[unitIndex]}';
  }

  /// 从 `content://` 之类的 URI 里取一个兜底文件名。
  static String fileNameFromUri(String uri) {
    final clean = uri.split('?').first;
    final segment = clean.split('/').last;
    if (segment.isEmpty) return '未命名';
    try {
      return Uri.decodeComponent(segment);
    } catch (_) {
      return segment;
    }
  }

  /// 生成一个安全的临时文件名（去掉路径分隔符等非法字符）。
  static String safeFileName(String raw) {
    final sanitized = raw.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    return sanitized.isEmpty ? 'file' : sanitized;
  }
}
