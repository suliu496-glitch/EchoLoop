import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';

/// 应用私有目录管理。
///
/// 缩略图与录音都放在这里（应用私有沙盒），**不写用户媒体库**，
/// 卸载应用即彻底清理，符合需求 §4.3「不污染用户文件」与 §3.3「录音临时存储」。
class AppDirectories {
  AppDirectories();

  Directory? _cacheRoot;

  Future<Directory> get _root async {
    final cached = _cacheRoot;
    if (cached != null) return cached;
    // 用 support 目录而非 temp：temp 可能被系统随时清理，
    // 缩略图被清掉只是重新生成，但录音被清掉会打断跟读对比，放 support 更稳。
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'echoloop'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    _cacheRoot = root;
    return root;
  }

  Future<Directory> thumbnails() => _ensure(AppConstants.thumbnailDirName);

  Future<Directory> recordings() => _ensure(AppConstants.recordingDirName);

  Future<Directory> _ensure(String name) async {
    final root = await _root;
    final directory = Directory(p.join(root.path, name));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// 生成录音输出路径：`recordings/clip_<时间戳>.m4a`
  Future<String> newRecordingPath() async {
    final directory = await recordings();
    return p.join(
      directory.path,
      'clip_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
  }

  /// 清空录音目录（「一键删除录音」）。
  Future<void> clearRecordings() async {
    final directory = await recordings();
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is File) {
        await entity.delete().catchError((_) => entity);
      }
    }
  }

  /// 删除单个文件，静默失败（文件可能已不存在）。
  Future<void> deleteQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete().catchError((_) => file);
    }
  }
}
