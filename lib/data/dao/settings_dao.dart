import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../db/database_schema.dart';

/// 设置项读写。`settings` 表就是一张 key-value 表，
/// 整表读出来交给 [AppSettings.fromValues] 组装，避免每加一个设置就多一个查询。
class SettingsDao {
  SettingsDao(this._helper);

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.database;

  Future<Map<String, String>> loadAll() async {
    final db = await _db;
    final rows = await db.query(DatabaseSchema.tableSettings);
    return {
      for (final row in rows)
        if (row['key'] is String && row['value'] is String)
          row['key']! as String: row['value']! as String,
    };
  }

  Future<void> put(String key, String value) async {
    final db = await _db;
    await db.insert(
      DatabaseSchema.tableSettings,
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> putAll(Map<String, String> values) async {
    if (values.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    values.forEach((key, value) {
      batch.insert(
        DatabaseSchema.tableSettings,
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }

  Future<void> remove(String key) async {
    final db = await _db;
    await db.delete(
      DatabaseSchema.tableSettings,
      where: 'key = ?',
      whereArgs: [key],
    );
  }
}
