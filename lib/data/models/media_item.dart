import '../../core/utils/file_utils.dart';

/// 媒体类型。
enum MediaKind {
  video('video'),
  audio('audio');

  const MediaKind(this.wire);

  /// 存库用的字符串
  final String wire;

  static MediaKind fromWire(String? value) =>
      value == 'video' ? MediaKind.video : MediaKind.audio;

  static MediaKind fromName(String fileName) =>
      FileUtils.isVideoName(fileName) ? MediaKind.video : MediaKind.audio;
}

/// 循环模式（需求 §3.1-3）。
enum LoopMode {
  /// 未启用循环
  off('off'),

  /// 无限循环
  infinite('infinite'),

  /// 指定遍数循环
  count('count');

  const LoopMode(this.wire);

  final String wire;

  static LoopMode fromWire(String? value) => switch (value) {
        'infinite' => LoopMode.infinite,
        'count' => LoopMode.count,
        _ => LoopMode.off,
      };
}

/// 媒体库条目。
///
/// 注意：这里保存的 [uri] 只是**引用**，不复制也不移动用户的原文件
/// （需求 §4.3）；删除媒体库条目只会删掉这条记录和字幕数据。
class MediaItem {
  const MediaItem({
    this.id,
    required this.uri,
    required this.name,
    required this.kind,
    this.mimeType = '',
    this.durationMs = 0,
    this.sizeBytes = 0,
    this.thumbnailPath,
    this.lastPlayedAt,
    this.positionMs = 0,
    this.loopStartMs,
    this.loopEndMs,
    this.loopMode = LoopMode.off,
    this.loopCount = 1,
    required this.createdAt,
  });

  final int? id;
  final String uri;
  final String name;
  final MediaKind kind;
  final String mimeType;
  final int durationMs;
  final int sizeBytes;

  /// 视频首帧缩略图的本地缓存路径
  final String? thumbnailPath;

  /// 最近播放时间（epoch 毫秒），为空表示从未播放
  final int? lastPlayedAt;

  /// 上次播放位置，用于下次进入时续播
  final int positionMs;

  // --- 以下 4 个字段是需求 §4.2「循环区间单文件独立存储」的落点 ---
  final int? loopStartMs;
  final int? loopEndMs;
  final LoopMode loopMode;
  final int loopCount;

  final int createdAt;

  bool get isVideo => kind == MediaKind.video;

  /// 是否存在有效的 AB 片段
  bool get hasLoopRegion {
    final start = loopStartMs;
    final end = loopEndMs;
    return start != null && end != null && end > start;
  }

  /// 播放进度百分比，用于列表页的细进度条
  double get progressRatio {
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  MediaItem copyWith({
    int? id,
    String? uri,
    String? name,
    MediaKind? kind,
    String? mimeType,
    int? durationMs,
    int? sizeBytes,
    String? thumbnailPath,
    int? lastPlayedAt,
    int? positionMs,
    int? loopStartMs,
    int? loopEndMs,
    LoopMode? loopMode,
    int? loopCount,
    int? createdAt,
    bool clearLoopRegion = false,
  }) {
    return MediaItem(
      id: id ?? this.id,
      uri: uri ?? this.uri,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      mimeType: mimeType ?? this.mimeType,
      durationMs: durationMs ?? this.durationMs,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      positionMs: positionMs ?? this.positionMs,
      loopStartMs: clearLoopRegion ? null : (loopStartMs ?? this.loopStartMs),
      loopEndMs: clearLoopRegion ? null : (loopEndMs ?? this.loopEndMs),
      loopMode: loopMode ?? this.loopMode,
      loopCount: loopCount ?? this.loopCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    final map = <String, Object?>{
      'uri': uri,
      'name': name,
      'kind': kind.wire,
      'mime_type': mimeType,
      'duration_ms': durationMs,
      'size_bytes': sizeBytes,
      'thumbnail_path': thumbnailPath,
      'last_played_at': lastPlayedAt,
      'position_ms': positionMs,
      'loop_start_ms': loopStartMs,
      'loop_end_ms': loopEndMs,
      'loop_mode': loopMode.wire,
      'loop_count': loopCount,
      'created_at': createdAt,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  factory MediaItem.fromMap(Map<String, Object?> map) {
    return MediaItem(
      id: map['id'] as int?,
      uri: (map['uri'] as String?) ?? '',
      name: (map['name'] as String?) ?? '未命名',
      kind: MediaKind.fromWire(map['kind'] as String?),
      mimeType: (map['mime_type'] as String?) ?? '',
      durationMs: (map['duration_ms'] as int?) ?? 0,
      sizeBytes: (map['size_bytes'] as int?) ?? 0,
      thumbnailPath: map['thumbnail_path'] as String?,
      lastPlayedAt: map['last_played_at'] as int?,
      positionMs: (map['position_ms'] as int?) ?? 0,
      loopStartMs: map['loop_start_ms'] as int?,
      loopEndMs: map['loop_end_ms'] as int?,
      loopMode: LoopMode.fromWire(map['loop_mode'] as String?),
      loopCount: (map['loop_count'] as int?) ?? 1,
      createdAt: (map['created_at'] as int?) ?? 0,
    );
  }
}
