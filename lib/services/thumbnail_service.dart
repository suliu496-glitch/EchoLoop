import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/constants/app_constants.dart';
import '../data/models/media_item.dart';
import 'app_directories.dart';
import 'native_channel.dart';

/// 视频封面缩略图服务。
///
/// 抽帧放在原生侧做（MediaMetadataRetriever），好处是不占 Dart 侧的内存，
/// 1080p 视频抽一帧的位图直接由原生缩放成 JPEG，避免把大图搬过通道。
class ThumbnailService {
  ThumbnailService({
    required NativeChannel channel,
    required AppDirectories directories,
  })  : _channel = channel,
        _directories = directories;

  final NativeChannel _channel;
  final AppDirectories _directories;

  /// 为视频生成封面；纯音频或抽帧失败返回 null（UI 用图标占位）。
  Future<String?> generateFor(MediaItem item) async {
    if (!item.isVideo || item.id == null) return null;

    // 已存在就不重复抽帧
    final existing = item.thumbnailPath;
    if (existing != null && await File(existing).exists()) return existing;

    final directory = await _directories.thumbnails();
    final outPath = p.join(directory.path, 'thumb_${item.id}.jpg');

    try {
      final path = await _channel.createThumbnail(
        uri: item.uri,
        outPath: outPath,
        timeMs: -1,
        maxWidth: AppConstants.thumbnailMaxWidth,
      );
      if (path == null || path.isEmpty) return null;
      return path;
    } catch (_) {
      // 抽帧失败是可接受的降级：列表用图标占位继续可用
      return null;
    }
  }

  /// 删除媒体时一并清掉封面缓存。
  Future<void> removeFor(MediaItem item) =>
      _directories.deleteQuietly(item.thumbnailPath);
}
