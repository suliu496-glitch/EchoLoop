/// 应用统一异常类型。
///
/// 项目里所有「可预期」的失败（文件读不到、字幕格式错、解码失败……）
/// 都包成 [AppException]，由 UI 层统一转成可读提示，
/// 避免出现白屏或静默失败（对应需求 §9.3）。
class AppException implements Exception {
  const AppException(this.message, {this.detail, this.code});

  /// 面向用户的可读提示
  final String message;

  /// 面向排查的技术细节，界面上折叠展示
  final String? detail;

  /// 机器可读的错误码
  final String? code;

  @override
  String toString() => detail == null ? message : '$message（$detail）';
}

/// 播放相关失败
class PlaybackException extends AppException {
  const PlaybackException(super.message, {super.detail, super.code});
}

/// 媒体导入相关失败
class MediaImportException extends AppException {
  const MediaImportException(super.message, {super.detail, super.code});
}

/// 字幕相关失败
class SubtitleException extends AppException {
  const SubtitleException(super.message, {super.detail, super.code});
}

/// 把任意异常转成一句能给人看的提示。
String humanizeError(Object error) {
  if (error is AppException) return error.message;
  return '操作失败：$error';
}
