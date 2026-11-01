import '../core/errors/app_exception.dart';
import '../core/utils/file_utils.dart';
import '../data/dao/subtitle_dao.dart';
import '../data/models/subtitle_models.dart';
import '../domain/subtitles/subtitle_cue.dart';
import '../domain/subtitles/subtitle_parser.dart';
import 'native_channel.dart';
import 'transcriber/transcriber.dart';

/// 字幕业务服务。
///
/// 承担三件事：
/// 1. 把外部内容（文件 / AI 结果）解析成字幕句并落库；
/// 2. 提供「激活轨 → 字幕句 → SubtitleCue」的转换，供播放页高亮与吸附使用；
/// 3. 字幕编辑的增删改（含序号重排）。
class SubtitleService {
  SubtitleService({required NativeChannel channel, required SubtitleDao dao})
    : _channel = channel,
      _dao = dao;

  final NativeChannel _channel;
  final SubtitleDao _dao;

  /// 手动新建字幕时的默认单句时长：新句没有下一句参考，先给 3 秒。
  static const int defaultLineDurationMs = 3000;

  // ------------------------------------------------------------------
  // 导入
  // ------------------------------------------------------------------

  /// 弹出系统文件选择器并导入字幕。用户取消返回 null。
  Future<SubtitleTrack?> importFromPicker(int mediaId) async {
    final picked = await _channel.pickSubtitleFile();
    if (picked == null) return null;

    final extension = FileUtils.extensionOf(picked.name);
    if (!SubtitleParserRegistry.supportedExtensions.contains(extension)) {
      throw SubtitleException(
        '不支持的字幕格式 .$extension',
        detail:
            '当前支持：${SubtitleParserRegistry.supportedExtensions.join(' / ')}',
        code: 'unsupported_subtitle_format',
      );
    }
    return importFromContent(
      mediaId: mediaId,
      name: FileUtils.stripExtension(picked.name),
      content: picked.content,
      extension: extension,
    );
  }

  /// 从文本内容导入（也是 AI 识别结果落库的统一入口）。
  Future<SubtitleTrack> importFromContent({
    required int mediaId,
    required String name,
    required String content,
    required String extension,
    SubtitleSource source = SubtitleSource.imported,
  }) async {
    final cues = SubtitleParserRegistry.parse(content, extension);
    return _persistCues(
      mediaId: mediaId,
      name: name.isEmpty ? '字幕' : name,
      cues: cues,
      source: source,
    );
  }

  /// 把 AI 识别结果写入一条新字幕轨（需求 §3.2-6 的落地路径）。
  ///
  /// 识别器只管产出 [TranscriptSegment]，落库、来源标识、激活状态都由这里统一处理。
  Future<SubtitleTrack> importFromTranscriber({
    required int mediaId,
    required String mediaUri,
    required String mediaName,
    required Transcriber transcriber,
    TranscriberProgress? onProgress,
  }) async {
    final segments = await transcriber.transcribe(
      mediaUri: mediaUri,
      mediaName: mediaName,
      onProgress: onProgress,
    );
    if (segments.isEmpty) {
      throw const SubtitleException(
        '识别完成但没有得到字幕内容',
        detail: '可能是纯音乐、静音片段或服务返回空结果',
        code: 'empty_transcript',
      );
    }

    final cues = <SubtitleCue>[
      for (var i = 0; i < segments.length; i++)
        SubtitleCue(
          index: i + 1,
          startMs: segments[i].startMs,
          endMs: segments[i].endMs,
          text: segments[i].text,
        ),
    ];

    return _persistCues(
      mediaId: mediaId,
      name: transcriber.displayName,
      cues: cues,
      source: SubtitleSource.ai,
      replaceActiveTracks: true,
    );
  }

  Future<SubtitleTrack> _persistCues({
    required int mediaId,
    required String name,
    required List<SubtitleCue> cues,
    required SubtitleSource source,
    bool replaceActiveTracks = false,
  }) async {
    if (replaceActiveTracks) {
      await _dao.deactivateAllTracks(mediaId);
      await _dao.deleteTracksByName(mediaId, name);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final trackId = await _dao.insertTrack(
      SubtitleTrack(
        mediaId: mediaId,
        name: name,
        language: '',
        source: source,
        isActive: true,
        createdAt: now,
      ),
    );

    await _dao.insertLines([
      for (final cue in cues)
        SubtitleLine(
          mediaId: mediaId,
          trackId: trackId,
          lineIndex: cue.index - 1,
          startMs: cue.startMs,
          endMs: cue.endMs,
          text: cue.text,
          source: source,
        ),
    ]);

    // 新导入的字幕自动接管显示，用户之前激活的轨保持激活（支持双语同显）
    return SubtitleTrack(
      id: trackId,
      mediaId: mediaId,
      name: name,
      source: source,
      isActive: true,
      createdAt: now,
    );
  }

  /// 手动新建一条空字幕轨（「添加字幕」按钮用）。
  Future<SubtitleTrack> createManualTrack(
    int mediaId, {
    String name = '我的手写字幕',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final trackId = await _dao.insertTrack(
      SubtitleTrack(
        mediaId: mediaId,
        name: name,
        source: SubtitleSource.manual,
        isActive: true,
        createdAt: now,
      ),
    );
    return SubtitleTrack(
      id: trackId,
      mediaId: mediaId,
      name: name,
      source: SubtitleSource.manual,
      isActive: true,
      createdAt: now,
    );
  }

  // ------------------------------------------------------------------
  // 查询
  // ------------------------------------------------------------------

  Future<List<SubtitleTrack>> tracksOf(int mediaId) => _dao.tracksOf(mediaId);

  Future<List<SubtitleLine>> linesOfTrack(int trackId) =>
      _dao.linesOfTrack(trackId);

  /// 当前激活轨的全部字幕句。
  Future<List<SubtitleLine>> activeLinesOf(int mediaId) =>
      _dao.activeLinesOf(mediaId);

  /// 转成域模型，供高亮与吸附算法使用。
  Future<List<SubtitleCue>> activeCuesOf(int mediaId) async {
    final lines = await _dao.activeLinesOf(mediaId);
    return toCues(lines);
  }

  /// [SubtitleLine] → [SubtitleCue]，统一在这里做，避免各处重复写。
  static List<SubtitleCue> toCues(List<SubtitleLine> lines) {
    return [
      for (var i = 0; i < lines.length; i++)
        SubtitleCue(
          index: i + 1,
          startMs: lines[i].startMs,
          endMs: lines[i].endMs,
          text: lines[i].text,
        ),
    ];
  }

  // ------------------------------------------------------------------
  // 编辑
  // ------------------------------------------------------------------

  /// 在指定时间点新增一句。
  ///
  /// [endMs] 不传时按「下一句起点」推算；没有下一句就用默认 3 秒。
  Future<SubtitleLine> addLine({
    required int mediaId,
    required int trackId,
    required int startMs,
    String text = '',
    int? endMs,
  }) async {
    final existing = await _dao.linesOfTrack(trackId);
    int resolvedEnd;
    if (endMs != null) {
      resolvedEnd = endMs;
    } else {
      final next = existing.where((line) => line.startMs > startMs).toList()
        ..sort((a, b) => a.startMs.compareTo(b.startMs));
      resolvedEnd = next.isEmpty
          ? startMs + defaultLineDurationMs
          : next.first.startMs;
      if (resolvedEnd - startMs < 300) {
        resolvedEnd = startMs + defaultLineDurationMs;
      }
    }

    final id = await _dao.insertLine(
      SubtitleLine(
        mediaId: mediaId,
        trackId: trackId,
        lineIndex: existing.length,
        startMs: startMs,
        endMs: resolvedEnd,
        text: text,
        source: SubtitleSource.manual,
      ),
    );
    await _dao.reindexTrack(trackId);

    final refreshed = await _dao.linesOfTrack(trackId);
    return refreshed.firstWhere(
      (line) => line.id == id,
      orElse: () => SubtitleLine(
        id: id,
        mediaId: mediaId,
        trackId: trackId,
        lineIndex: existing.length,
        startMs: startMs,
        endMs: resolvedEnd,
        text: text,
        source: SubtitleSource.manual,
      ),
    );
  }

  /// 更新一句（文本 / 起止时间）。
  Future<void> updateLine(SubtitleLine line) async {
    if (line.endMs <= line.startMs) {
      throw const SubtitleException('结束时间必须晚于开始时间', code: 'invalid_time_range');
    }
    await _dao.updateLine(line.copyWith(source: SubtitleSource.manual));
    await _dao.reindexTrack(line.trackId);
  }

  Future<void> deleteLine(int trackId, int lineId) async {
    await _dao.deleteLine(lineId);
    await _dao.reindexTrack(trackId);
  }

  Future<void> deleteTrack(int trackId) => _dao.deleteTrack(trackId);

  Future<void> renameTrack(int trackId, String name) =>
      _dao.renameTrack(trackId, name);

  /// 单条轨的显示开关（单语模式）。
  Future<void> toggleTrackExclusive(
    int mediaId,
    int trackId,
    bool active,
  ) async {
    if (active) {
      await _dao.setExclusiveActive(mediaId, trackId);
    } else {
      await _dao.setTrackActive(trackId, false);
    }
  }

  /// 追加显示某条轨（双语同显）。
  Future<void> setTrackActive(int trackId, bool active) =>
      _dao.setTrackActive(trackId, active);

  /// 清空某条轨的全部字幕。
  Future<void> clearTrack(int trackId) async {
    await _dao.deleteLinesOfTrack(trackId);
  }

  /// 删除媒体时把字幕一起清掉（外键级联已经覆盖，这里提供给「不依赖外键」的兜底场景）。
  Future<void> deleteAllOfMedia(int mediaId) async {
    final tracks = await _dao.tracksOf(mediaId);
    for (final track in tracks) {
      final id = track.id;
      if (id != null) await _dao.deleteTrack(id);
    }
  }

  /// 把异常统一转成 [AppException]（给 UI 直接用）。
  static AppException asAppException(Object error) {
    if (error is AppException) return error;
    return AppException('字幕处理失败', detail: error.toString());
  }
}
