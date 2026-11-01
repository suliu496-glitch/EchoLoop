import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../db/database_schema.dart';
import '../models/media_item.dart';

/// 媒体库数据访问对象。
class MediaDao {
  MediaDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.database;

  /// 媒体库列表。默认「最近播放优先」，从未播放的排在后面按导入时间倒序。
  Future<List<MediaItem>> listAll({String keyword = ''}) async {
    final db = await _db;
    final trimmed = keyword.trim();
    final rows = await db.query(
      DatabaseSchema.tableMedia,
      where: trimmed.isEmpty ? null : 'name LIKE ?',
      whereArgs: trimmed.isEmpty ? null : ['%$trimmed%'],
      orderBy: 'last_played_at IS NULL, last_played_at DESC, created_at DESC',
    );
    return rows.map(MediaItem.fromMap).toList();
  }

  Future<MediaItem?> findById(int id) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableMedia,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : MediaItem.fromMap(rows.first);
  }

  /// 按 URI 查重，避免同一个文件被重复导入。
  Future<MediaItem?> findByUri(String uri) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableMedia,
      where: 'uri = ?',
      whereArgs: [uri],
      limit: 1,
    );
    return rows.isEmpty ? null : MediaItem.fromMap(rows.first);
  }

  Future<int> insert(MediaItem item) async {
    final db = await _db;
    return db.insert(
      DatabaseSchema.tableMedia,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(MediaItem item) async {
    final id = item.id;
    if (id == null) return;
    final db = await _db;
    await db.update(
      DatabaseSchema.tableMedia,
      item.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 只更新名字（重命名）。
  Future<void> rename(int id, String name) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.tableMedia,
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateThumbnail(int id, String? path) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.tableMedia,
      {'thumbnail_path': path},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 补全缺失的媒体时长，只更新该字段，避免覆盖同时保存的选区和进度。
  Future<void> updateDurationIfMissing(int id, int durationMs) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.tableMedia,
      {'duration_ms': durationMs},
      where: 'id = ? AND duration_ms = 0',
      whereArgs: [id],
    );
  }

  /// 记录播放进度与最近播放时间。
  Future<void> updateProgress(
    int id, {
    required int positionMs,
    required int lastPlayedAt,
  }) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.tableMedia,
      {'position_ms': positionMs, 'last_played_at': lastPlayedAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 保存该文件的循环区间（需求 §4.2：单文件独立存储）。
  Future<void> updateLoopRegion(
    int id, {
    int? startMs,
    int? endMs,
    required LoopMode mode,
    required int count,
  }) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.tableMedia,
      {
        'loop_start_ms': startMs,
        'loop_end_ms': endMs,
        'loop_mode': mode.wire,
        'loop_count': count,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 清除该文件的循环区间。
  Future<void> clearLoopRegion(int id) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.tableMedia,
      {
        'loop_start_ms': null,
        'loop_end_ms': null,
        'loop_mode': LoopMode.off.wire,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 删除媒体库条目。原文件不受影响（外键级联会清掉字幕与收藏）。
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.tableMedia,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DatabaseSchema.tableMedia}',
    );
    return (result.first['c'] as int?) ?? 0;
  }
}
