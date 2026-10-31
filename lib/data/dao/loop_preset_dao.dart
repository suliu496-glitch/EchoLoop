import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../db/database_schema.dart';
import '../models/loop_preset.dart';

/// 片段收藏数据访问对象。
class LoopPresetDao {
  LoopPresetDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.database;

  Future<List<LoopPreset>> listOf(int mediaId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseSchema.tableLoopPreset,
      where: 'media_id = ?',
      whereArgs: [mediaId],
      orderBy: 'created_at DESC',
    );
    return rows.map(LoopPreset.fromMap).toList();
  }

  Future<int> insert(LoopPreset preset) async {
    final db = await _db;
    return db.insert(DatabaseSchema.tableLoopPreset, preset.toMap());
  }

  Future<void> updateNote(int presetId, String note) async {
    final db = await _db;
    await db.update(
      DatabaseSchema.tableLoopPreset,
      {'note': note},
      where: 'id = ?',
      whereArgs: [presetId],
    );
  }

  Future<void> delete(int presetId) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.tableLoopPreset,
      where: 'id = ?',
      whereArgs: [presetId],
    );
  }
}
