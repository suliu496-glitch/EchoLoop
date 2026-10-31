import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../db/database_schema.dart';
import '../models/subtitle_models.dart';

/// 字幕数据访问对象：同时管 `subtitle_track` 与 `subtitle` 两张表。
///
/// 两张表放一个 DAO 是因为它们的生命周期完全绑定：
/// 任何一次「导入字幕」「AI 识别」都是先建轨、再批量写句，拆开反而要跨 DAO 传事务。
class SubtitleDao {
  SubtitleDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.database;

  // ------------------------------------------------------------------
  // 字幕轨
  // ------------------------------------------------------------------

  Future<List<SubtitleTrack>> tracksOf(int mediaId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableSubtitleTrack,
      where: 'media_id = ?',
      whereArgs: [mediaId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(SubtitleTrack.fromMap).toList();
  }

  Future<int> insertTrack(SubtitleTrack track) async {
    final db = await _db;
    return db.insert(DatabaseSchema.tableSubtitleTrack, track.toMap());
  }

  Future<void> renameTrack(int trackId, String name) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.tableSubtitleTrack,
      {'name': name},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  /// 切换某条轨道的显示状态（支持多条同时激活，对应双语同时显示）。
  Future<void> setTrackActive(int trackId, bool active) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.tableSubtitleTrack,
      {'is_active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  /// Turn off all existing tracks before activating an automatically generated
  /// sentence track, so the precision-list view does not interleave old cues.
  Future<void> deactivateAllTracks(int mediaId) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.tableSubtitleTrack,
      {'is_active': 0},
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
  }

  Future<void> deleteTracksByName(int mediaId, String name) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        DatabaseSchema.tableSubtitle,
        where:
            'track_id IN (SELECT id FROM ${DatabaseSchema.tableSubtitleTrack} '
            'WHERE media_id = ? AND name = ?)',
        whereArgs: [mediaId, name],
      );
      await txn.delete(
        DatabaseSchema.tableSubtitleTrack,
        where: 'media_id = ? AND name = ?',
        whereArgs: [mediaId, name],
      );
    });
  }

  /// 只保留一条激活轨（单语显示模式）。
  Future<void> setExclusiveActive(int mediaId, int trackId) async {
    final db = await _db;
    final batch = db.batch();
    batch.update(
      DatabaseSchema.tableSubtitleTrack,
      {'is_active': 0},
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    batch.update(
      DatabaseSchema.tableSubtitleTrack,
      {'is_active': 1},
      where: 'id = ?',
      whereArgs: [trackId],
    );
    await batch.commit(noResult: true);
  }

  Future<void> deleteTrack(int trackId) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.tableSubtitleTrack,
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  // ------------------------------------------------------------------
  // 字幕单句
  // ------------------------------------------------------------------

  Future<List<SubtitleLine>> linesOfTrack(int trackId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableSubtitle,
      where: 'track_id = ?',
      whereArgs: [trackId],
      orderBy: 'start_ms ASC, line_index ASC',
    );
    return rows.map(SubtitleLine.fromMap).toList();
  }

  /// 取当前媒体下所有「激活轨道」的字幕句，按时间排序。
  /// 播放页的字幕列表、以及 AB 边界吸附都用这一份数据。
  Future<List<SubtitleLine>> activeLinesOf(int mediaId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT s.* FROM ${DatabaseSchema.tableSubtitle} s
      INNER JOIN ${DatabaseSchema.tableSubtitleTrack} t ON t.id = s.track_id
      WHERE s.media_id = ? AND t.is_active = 1
      ORDER BY s.start_ms ASC, s.line_index ASC
      ''',
      [mediaId],
    );
    return rows.map(SubtitleLine.fromMap).toList();
  }

  Future<int> insertLine(SubtitleLine line) async {
    final db = await _db;
    return db.insert(DatabaseSchema.tableSubtitle, line.toMap());
  }

  /// 批量写入（导入整份字幕时用），走事务保证要么全成功要么全失败。
  Future<void> insertLines(List<SubtitleLine> lines) async {
    if (lines.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final line in lines) {
      batch.insert(DatabaseSchema.tableSubtitle, line.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateLine(SubtitleLine line) async {
    final id = line.id;
    if (id == null) return;
    final db = await _db;
    await db.update(
      DatabaseSchema.tableSubtitle,
      line.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteLine(int lineId) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.tableSubtitle,
      where: 'id = ?',
      whereArgs: [lineId],
    );
  }

  Future<void> deleteLinesOfTrack(int trackId) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.tableSubtitle,
      where: 'track_id = ?',
      whereArgs: [trackId],
    );
  }

  /// 重排序号：插入 / 删除后调用，保证 line_index 连续。
  Future<void> reindexTrack(int trackId) async {
    final db = await _db;
    final lines = await linesOfTrack(trackId);
    final batch = db.batch();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.lineIndex == i) continue;
      batch.update(
        DatabaseSchema.tableSubtitle,
        {'line_index': i},
        where: 'id = ?',
        whereArgs: [line.id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> countLinesOfTrack(int trackId) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DatabaseSchema.tableSubtitle} WHERE track_id = ?',
      [trackId],
    );
    return (result.first['c'] as int?) ?? 0;
  }
}
