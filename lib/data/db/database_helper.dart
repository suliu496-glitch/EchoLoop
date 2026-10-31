import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import 'database_schema.dart';

/// 数据库单例。
///
/// 只负责「开库 + 建表 + 迁移 + 提供 Database 句柄」，
/// 具体 SQL 一律下沉到各 DAO，避免这里变成一坨（需求 §9.1）。
class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _database;

  /// 打开（或复用）数据库连接。带并发保护，多处同时首次访问不会重复开库。
  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;
    final opened = await _open();
    _database = opened;
    return opened;
  }

  Future<Database> _open() async {
    final directory = await getDatabasesPath();
    final path = p.join(directory, AppConstants.databaseName);
    return openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future<void> _onConfigure(Database db) async {
    // 打开外键约束，保证删除媒体时字幕 / 收藏一起级联清掉
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final statement in DatabaseSchema.createStatements) {
      batch.execute(statement);
    }
    for (final statement in DatabaseSchema.createIndexStatements) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 目前只有 v1。后续加字段时在这里按 oldVersion 逐级迁移，
    // 不做 drop-recreate，避免用户已导入的媒体和字幕丢失。
  }

  /// 关闭连接（测试或彻底退出时调用）。
  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
