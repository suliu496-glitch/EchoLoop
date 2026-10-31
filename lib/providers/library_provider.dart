import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../data/dao/media_dao.dart';
import '../data/models/media_item.dart';
import '../services/media_import_service.dart';
import '../services/native_channel.dart';
import '../services/thumbnail_service.dart';
import 'core_providers.dart';

/// 媒体库界面状态。
class MediaLibraryState {
  const MediaLibraryState({
    this.items = const [],
    this.loading = false,
    this.keyword = '',
    this.error,
    this.deviceEntries,
    this.scanningDevice = false,
  });

  /// 媒体库列表（最近播放优先）
  final List<MediaItem> items;

  final bool loading;

  /// 搜索关键字
  final String keyword;

  /// 最近一次操作的错误提示（读走后就清空）
  final String? error;

  /// 设备媒体扫描结果（仅在选择面板打开时有值）
  final List<NativeMediaEntry>? deviceEntries;

  final bool scanningDevice;

  bool get isEmpty => items.isEmpty && !loading;

  MediaLibraryState copyWith({
    List<MediaItem>? items,
    bool? loading,
    String? keyword,
    String? error,
    bool clearError = false,
    List<NativeMediaEntry>? deviceEntries,
    bool clearDeviceEntries = false,
    bool? scanningDevice,
  }) {
    return MediaLibraryState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      keyword: keyword ?? this.keyword,
      error: clearError ? null : (error ?? this.error),
      deviceEntries: clearDeviceEntries ? null : (deviceEntries ?? this.deviceEntries),
      scanningDevice: scanningDevice ?? this.scanningDevice,
    );
  }
}

/// 媒体库业务逻辑。
class MediaLibraryNotifier extends StateNotifier<MediaLibraryState> {
  MediaLibraryNotifier({
    required MediaDao mediaDao,
    required MediaImportService importService,
    required ThumbnailService thumbnailService,
  })  : _mediaDao = mediaDao,
        _importService = importService,
        _thumbnailService = thumbnailService,
        super(const MediaLibraryState(loading: true)) {
    refresh();
  }

  final MediaDao _mediaDao;
  final MediaImportService _importService;
  final ThumbnailService _thumbnailService;

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final items = await _mediaDao.listAll(keyword: state.keyword);
      state = state.copyWith(items: items, loading: false);
    } catch (error) {
      state = state.copyWith(
        loading: false,
        error: humanizeError(error),
      );
    }
  }

  void setKeyword(String keyword) {
    state = state.copyWith(keyword: keyword);
    refresh();
  }

  /// 通过系统文件选择器导入，返回结果给 UI 做提示。用户取消返回 null。
  Future<MediaImportResult?> importFromPicker() async {
    try {
      final result = await _importService.importFromSystemPicker();
      if (result.isEmpty) return null;
      await refresh();
      return result;
    } catch (error) {
      state = state.copyWith(error: humanizeError(error));
      return null;
    }
  }

  /// 打开设备媒体选择面板：扫描一次 MediaStore。
  Future<void> scanDeviceMedia({String scope = 'all', String keyword = ''}) async {
    state = state.copyWith(scanningDevice: true, clearError: true);
    try {
      final entries = await _importService.scanDeviceMedia(
        scope: scope,
        keyword: keyword,
      );
      state = state.copyWith(
        deviceEntries: entries,
        scanningDevice: false,
      );
    } catch (error) {
      state = state.copyWith(
        scanningDevice: false,
        clearDeviceEntries: true,
        error: humanizeError(error),
      );
    }
  }

  void closeDevicePanel() {
    state = state.copyWith(clearDeviceEntries: true);
  }

  /// 导入用户从设备媒体里勾选的条目。
  Future<MediaImportResult?> importDeviceEntries(List<NativeMediaEntry> entries) async {
    if (entries.isEmpty) return null;
    try {
      final result = await _importService.importEntries(entries);
      await refresh();
      return result;
    } catch (error) {
      state = state.copyWith(error: humanizeError(error));
      return null;
    }
  }

  Future<void> rename(int mediaId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    try {
      await _mediaDao.rename(mediaId, trimmed);
      await refresh();
    } catch (error) {
      state = state.copyWith(error: humanizeError(error));
    }
  }

  /// 删除媒体库条目：只删记录与本地缓存，**不动用户的原始文件**（需求 §4.3）。
  Future<void> remove(int mediaId) async {
    try {
      final item = await _mediaDao.findById(mediaId);
      if (item != null) {
        await _thumbnailService.removeFor(item);
      }
      await _mediaDao.delete(mediaId);
      await refresh();
    } catch (error) {
      state = state.copyWith(error: humanizeError(error));
    }
  }

  void consumeError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}

final mediaLibraryProvider =
    StateNotifierProvider<MediaLibraryNotifier, MediaLibraryState>((ref) {
  return MediaLibraryNotifier(
    mediaDao: ref.watch(mediaDaoProvider),
    importService: ref.watch(mediaImportServiceProvider),
    thumbnailService: ref.watch(thumbnailServiceProvider),
  );
});
