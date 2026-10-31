/// 片段收藏。
///
/// 对应数据库 `loop_preset` 表：把调好的 AB 片段存下来，配合备注，
/// 下次可以直接载入重练，不用再拖一次。
class LoopPreset {
  const LoopPreset({
    this.id,
    required this.mediaId,
    required this.startMs,
    required this.endMs,
    this.note = '',
    required this.createdAt,
  });

  final int? id;
  final int mediaId;
  final int startMs;
  final int endMs;
  final String note;
  final int createdAt;

  int get durationMs => endMs - startMs;

  LoopPreset copyWith({
    int? id,
    int? mediaId,
    int? startMs,
    int? endMs,
    String? note,
    int? createdAt,
  }) {
    return LoopPreset(
      id: id ?? this.id,
      mediaId: mediaId ?? this.mediaId,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    final map = <String, Object?>{
      'media_id': mediaId,
      'start_ms': startMs,
      'end_ms': endMs,
      'note': note,
      'created_at': createdAt,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory LoopPreset.fromMap(Map<String, Object?> map) {
    return LoopPreset(
      id: map['id'] as int?,
      mediaId: (map['media_id'] as int?) ?? 0,
      startMs: (map['start_ms'] as int?) ?? 0,
      endMs: (map['end_ms'] as int?) ?? 0,
      note: (map['note'] as String?) ?? '',
      createdAt: (map['created_at'] as int?) ?? 0,
    );
  }
}
