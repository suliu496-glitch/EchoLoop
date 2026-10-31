/// SQLite 表结构定义（需求 §5 的表设计）。
///
/// 单独抽出这个文件的目的：表结构是「契约」，字幕解析、循环引擎、DAO
/// 都建立在它之上，集中放一处便于对照需求核查，也方便写进交付文档。
///
/// 相对需求给出的字段清单，有 5 处**补充字段**，都是为了落实需求正文里的规则：
/// 1. `media.loop_start_ms / loop_end_ms / loop_mode / loop_count`
///    —— 需求 §4.2 要求「循环区间为单文件独立存储」，需求给的 media 字段里没有落点；
/// 2. `subtitle_track.is_active`
///    —— 需求 §4.3 要求「可切换显示哪一条，也可同时显示」，需要记录激活状态。
class DatabaseSchema {
  DatabaseSchema._();

  static const String tableMedia = 'media';
  static const String tableSubtitle = 'subtitle';
  static const String tableSubtitleTrack = 'subtitle_track';
  static const String tableLoopPreset = 'loop_preset';
  static const String tableSettings = 'settings';

  /// 建表语句，按依赖顺序排列（先被引用的表在前）。
  static const List<String> createStatements = [
    '''
    CREATE TABLE $tableMedia (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      uri            TEXT    NOT NULL UNIQUE,
      name           TEXT    NOT NULL,
      kind           TEXT    NOT NULL,
      mime_type      TEXT    NOT NULL DEFAULT '',
      duration_ms    INTEGER NOT NULL DEFAULT 0,
      size_bytes     INTEGER NOT NULL DEFAULT 0,
      thumbnail_path TEXT,
      last_played_at INTEGER,
      position_ms    INTEGER NOT NULL DEFAULT 0,
      loop_start_ms  INTEGER,
      loop_end_ms    INTEGER,
      loop_mode      TEXT    NOT NULL DEFAULT 'off',
      loop_count     INTEGER NOT NULL DEFAULT 1,
      created_at     INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE $tableSubtitleTrack (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      media_id   INTEGER NOT NULL,
      name       TEXT    NOT NULL,
      language   TEXT    NOT NULL DEFAULT '',
      source     TEXT    NOT NULL DEFAULT 'imported',
      is_active  INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (media_id) REFERENCES $tableMedia (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE $tableSubtitle (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      media_id   INTEGER NOT NULL,
      track_id   INTEGER NOT NULL,
      line_index INTEGER NOT NULL,
      start_ms   INTEGER NOT NULL,
      end_ms     INTEGER NOT NULL,
      text       TEXT    NOT NULL,
      source     TEXT    NOT NULL DEFAULT 'imported',
      FOREIGN KEY (media_id) REFERENCES $tableMedia (id) ON DELETE CASCADE,
      FOREIGN KEY (track_id) REFERENCES $tableSubtitleTrack (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE $tableLoopPreset (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      media_id   INTEGER NOT NULL,
      start_ms   INTEGER NOT NULL,
      end_ms     INTEGER NOT NULL,
      note       TEXT    NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      FOREIGN KEY (media_id) REFERENCES $tableMedia (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE $tableSettings (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
  ];

  /// 索引：字幕按轨 + 时间排序读取是最高频查询，必须建。
  static const List<String> createIndexStatements = [
    'CREATE INDEX idx_subtitle_track ON $tableSubtitle (track_id, start_ms)',
    'CREATE INDEX idx_subtitle_media ON $tableSubtitle (media_id, start_ms)',
    'CREATE INDEX idx_track_media ON $tableSubtitleTrack (media_id)',
    'CREATE INDEX idx_preset_media ON $tableLoopPreset (media_id, created_at DESC)',
    'CREATE INDEX idx_media_recent ON $tableMedia (last_played_at DESC)',
  ];
}
