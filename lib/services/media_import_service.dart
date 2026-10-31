import '../core/constants/app_constants.dart';
import '../core/utils/file_utils.dart';
import '../data/dao/media_dao.dart';
import '../data/models/media_item.dart';
import 'native_channel.dart';
import 'thumbnail_service.dart';

/// 一次导入的结果，让 UI 能给出「导入 3 个，跳过 1 个已存在」这种明确反馈。
class MediaImportResult {
  const MediaImportResult({
    this.imported = const [],
    this.duplicated = const [],
    this.unsupported = const [],
  });

  /// 新入库的媒体
  final List<MediaItem> imported;

  /// 已经在库里的（按 URI 去重）
  final List<MediaItem> duplicated;

  /// 扩展名不在支持清单里的
  final List<String> unsupported;

  int get total => imported.length + duplicated.length + unsupported.length;

  bool get isEmpty => total == 0;

  /// 给 SnackBar 用的一句话总结。
  String get summary {
    final parts = <String>[];
    if (imported.isNotEmpty) parts.add('成功导入 ${imported.length} 个');
    if (duplicated.isNotEmpty) parts.add('${duplicated.length} 个已在库中');
    if (unsupported.isNotEmpty) parts.add('${unsupported.length} 个格式不支持');
    return parts.isEmpty ? '没有可导入的文件' : parts.join('，');
  }
}

/// 媒体导入服务。
///
/// 两条导入路线，都遵循「只存 URI 引用，不复制文件」：
/// 1. **系统文件选择器**（SAF）：能选到任意目录下的文件，URI 带持久化读取权限；
/// 2. **扫描设备媒体库**（MediaStore）：方便快速导入手机里已有的音频视频。
class MediaImportService {
  MediaImportService({
    required NativeChannel channel,
    required MediaDao mediaDao,
    required ThumbnailService thumbnailService,
  })  : _channel = channel,
        _mediaDao = mediaDao,
        _thumbnailService = thumbnailService;

  final NativeChannel _channel;
  final MediaDao _mediaDao;
  final ThumbnailService _thumbnailService;

  /// 通过系统文件选择器导入（支持多选）。
  Future<MediaImportResult> importFromSystemPicker() async {
    final entries = await _channel.pickMediaFiles(allowMultiple: true);
    return _persistEntries(entries);
  }

  /// 扫描设备上已有的音视频。
  Future<List<NativeMediaEntry>> scanDeviceMedia({
    String scope = 'all',
    String keyword = '',
  }) {
    return _channel.scanMediaStore(scope: scope, keyword: keyword);
  }

  /// 把扫描结果中用户勾选的条目入库。
  Future<MediaImportResult> importEntries(List<NativeMediaEntry> entries) =>
      _persistEntries(entries);

  Future<MediaImportResult> _persistEntries(List<NativeMediaEntry> entries) async {
    final imported = <MediaItem>[];
    final duplicated = <MediaItem>[];
    final unsupported = <String>[];

    for (final entry in entries) {
      if (entry.uri.isEmpty) continue;

      // 系统选择器给的 MIME 有时不可靠，这里再按扩展名把一次关
      final isSupported = FileUtils.isVideoName(entry.name) ||
          FileUtils.isAudioName(entry.name) ||
          entry.mimeType.startsWith('video/') ||
          entry.mimeType.startsWith('audio/');
      if (!isSupported) {
        unsupported.add(entry.name);
        continue;
      }

      // URI 去重：同一个文件重复导入只会留下一条记录
      final existing = await _mediaDao.findByUri(entry.uri);
      if (existing != null) {
        duplicated.add(existing);
        continue;
      }

      final item = MediaItem(
        uri: entry.uri,
        name: entry.name,
        kind: entry.isVideo || FileUtils.isVideoName(entry.name)
            ? MediaKind.video
            : MediaKind.audio,
        mimeType: entry.mimeType,
        durationMs: entry.durationMs,
        sizeBytes: entry.sizeBytes,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      final id = await _mediaDao.insert(item);
      final saved = item.copyWith(id: id);

      // 缩略图生成失败不影响导入，列表页会退化成图标占位
      final thumbnailPath = await _thumbnailService.generateFor(saved);
      if (thumbnailPath != null) {
        await _mediaDao.updateThumbnail(id, thumbnailPath);
        imported.add(saved.copyWith(thumbnailPath: thumbnailPath));
      } else {
        imported.add(saved);
      }
    }

    return MediaImportResult(
      imported: imported,
      duplicated: duplicated,
      unsupported: unsupported,
    );
  }

  /// 支持的扩展名清单（给「设备媒体」页做提示文案）
  List<String> get supportedExtensions => [
        ...AppConstants.videoExtensions,
        ...AppConstants.audioExtensions,
      ];
}
