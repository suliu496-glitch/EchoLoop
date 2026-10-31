/// 字幕条目的来源标识（需求 §3.2-6）。
///
/// 数据库里字幕表是通用结构，靠这个标识区分「手动导入 / 手动编辑 / AI 识别」，
/// 未来接入 AI 字幕时不需要改表，只要写入 [SubtitleSource.ai] 即可。
enum SubtitleSource {
  imported('imported'),
  manual('manual'),
  ai('ai');

  const SubtitleSource(this.wire);

  final String wire;

  static SubtitleSource fromWire(String? value) => switch (value) {
        'manual' => SubtitleSource.manual,
        'ai' => SubtitleSource.ai,
        _ => SubtitleSource.imported,
      };

  String get label => switch (this) {
        SubtitleSource.imported => '导入',
        SubtitleSource.manual => '手写',
        SubtitleSource.ai => 'AI 识别',
      };
}

/// 字幕轨（一个媒体可以有多条，例如中英双语、或者 AI 识别追加的一条）。
class SubtitleTrack {
  const SubtitleTrack({
    this.id,
    required this.mediaId,
    required this.name,
    this.language = '',
    this.source = SubtitleSource.imported,
    this.isActive = false,
    required this.createdAt,
  });

  final int? id;
  final int mediaId;
  final String name;
  final String language;
  final SubtitleSource source;

  /// 是否为当前显示的轨道。需求 §4.3 允许「切换显示哪一条，也可同时显示」，
  /// 因此这里允许多条同时为 true。
  final bool isActive;

  final int createdAt;

  SubtitleTrack copyWith({
    int? id,
    int? mediaId,
    String? name,
    String? language,
    SubtitleSource? source,
    bool? isActive,
    int? createdAt,
  }) {
    return SubtitleTrack(
      id: id ?? this.id,
      mediaId: mediaId ?? this.mediaId,
      name: name ?? this.name,
      language: language ?? this.language,
      source: source ?? this.source,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    final map = <String, Object?>{
      'media_id': mediaId,
      'name': name,
      'language': language,
      'source': source.wire,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory SubtitleTrack.fromMap(Map<String, Object?> map) {
    return SubtitleTrack(
      id: map['id'] as int?,
      mediaId: (map['media_id'] as int?) ?? 0,
      name: (map['name'] as String?) ?? '字幕',
      language: (map['language'] as String?) ?? '',
      source: SubtitleSource.fromWire(map['source'] as String?),
      isActive: ((map['is_active'] as int?) ?? 0) == 1,
      createdAt: (map['created_at'] as int?) ?? 0,
    );
  }
}

/// 字幕单句。
///
/// 时间单位统一毫秒（需求 §3.2-6 要求字幕表为通用结构），
/// 编辑界面上的「精确到毫秒」直接对应这里的 [startMs] / [endMs]。
class SubtitleLine {
  const SubtitleLine({
    this.id,
    required this.mediaId,
    required this.trackId,
    required this.lineIndex,
    required this.startMs,
    required this.endMs,
    required this.text,
    this.source = SubtitleSource.imported,
  });

  final int? id;
  final int mediaId;
  final int trackId;

  /// 轨内序号，从 0 开始，渲染时 +1 作为显示序号
  final int lineIndex;

  final int startMs;
  final int endMs;
  final String text;
  final SubtitleSource source;

  int get durationMs => endMs - startMs;

  bool containsMs(int ms) => ms >= startMs && ms < endMs;

  SubtitleLine copyWith({
    int? id,
    int? mediaId,
    int? trackId,
    int? lineIndex,
    int? startMs,
    int? endMs,
    String? text,
    SubtitleSource? source,
  }) {
    return SubtitleLine(
      id: id ?? this.id,
      mediaId: mediaId ?? this.mediaId,
      trackId: trackId ?? this.trackId,
      lineIndex: lineIndex ?? this.lineIndex,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      text: text ?? this.text,
      source: source ?? this.source,
    );
  }

  Map<String, Object?> toMap() {
    final map = <String, Object?>{
      'media_id': mediaId,
      'track_id': trackId,
      'line_index': lineIndex,
      'start_ms': startMs,
      'end_ms': endMs,
      'text': text,
      'source': source.wire,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory SubtitleLine.fromMap(Map<String, Object?> map) {
    return SubtitleLine(
      id: map['id'] as int?,
      mediaId: (map['media_id'] as int?) ?? 0,
      trackId: (map['track_id'] as int?) ?? 0,
      lineIndex: (map['line_index'] as int?) ?? 0,
      startMs: (map['start_ms'] as int?) ?? 0,
      endMs: (map['end_ms'] as int?) ?? 0,
      text: (map['text'] as String?) ?? '',
      source: SubtitleSource.fromWire(map['source'] as String?),
    );
  }
}
