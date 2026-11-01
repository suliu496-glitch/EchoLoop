import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../data/models/subtitle_models.dart';
import '../domain/subtitles/subtitle_cue.dart';
import '../domain/subtitles/subtitle_snapper.dart';
import '../services/subtitle_service.dart';
import '../services/transcriber/transcriber.dart';
import '../services/transcriber/whisper_transcriber.dart';
import 'core_providers.dart';
import 'settings_provider.dart';

/// 字幕界面状态。
class SubtitleState {
  const SubtitleState({
    this.mediaId,
    this.tracks = const [],
    this.lines = const [],
    this.cues = const [],
    this.loading = false,
    this.error,
    this.busyLabel,
    this.busyProgress,
  });

  final int? mediaId;

  /// 该媒体的全部字幕轨
  final List<SubtitleTrack> tracks;

  /// 当前激活轨合并后的字幕句（按时间升序）
  final List<SubtitleLine> lines;

  /// [lines] 的域模型形式，给高亮与吸附用
  final List<SubtitleCue> cues;

  final bool loading;

  final String? error;

  /// AI 识别这类耗时操作的阶段提示
  final String? busyLabel;
  final double? busyProgress;

  bool get hasSubtitles => lines.isNotEmpty;

  /// 激活轨（可能多条，支持双语同显）
  List<SubtitleTrack> get activeTracks =>
      tracks.where((track) => track.isActive).toList(growable: false);

  SubtitleState copyWith({
    int? mediaId,
    List<SubtitleTrack>? tracks,
    List<SubtitleLine>? lines,
    List<SubtitleCue>? cues,
    bool? loading,
    String? error,
    bool clearError = false,
    String? busyLabel,
    bool clearBusy = false,
    double? busyProgress,
  }) {
    return SubtitleState(
      mediaId: mediaId ?? this.mediaId,
      tracks: tracks ?? this.tracks,
      lines: lines ?? this.lines,
      cues: cues ?? this.cues,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      busyLabel: clearBusy ? null : (busyLabel ?? this.busyLabel),
      busyProgress: clearBusy ? null : (busyProgress ?? this.busyProgress),
    );
  }
}

/// 字幕业务逻辑（导入 / 编辑 / AI 识别入口 / 吸附）。
class SubtitleNotifier extends StateNotifier<SubtitleState> {
  SubtitleNotifier({
    required SubtitleService service,
    required Transcriber transcriber,
  }) : _service = service,
       _transcriber = transcriber,
       super(const SubtitleState());

  final SubtitleService _service;
  final Transcriber _transcriber;
  int _transcriptionGeneration = 0;

  /// 切换媒体时重新加载。
  Future<void> loadFor(int? mediaId) async {
    if (state.mediaId != mediaId) _transcriptionGeneration++;
    if (mediaId == null) {
      state = const SubtitleState();
      return;
    }
    if (state.mediaId == mediaId && !state.loading) {
      await _reload(mediaId);
      return;
    }
    state = SubtitleState(mediaId: mediaId, loading: true);
    await _reload(mediaId);
  }

  Future<void> _reload(int mediaId) async {
    try {
      final tracks = await _service.tracksOf(mediaId);
      final lines = await _service.activeLinesOf(mediaId);
      state = state.copyWith(
        mediaId: mediaId,
        tracks: tracks,
        lines: lines,
        cues: SubtitleService.toCues(lines),
        loading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: humanizeError(error));
    }
  }

  // ------------------------------------------------------------------
  // 导入 / 新建
  // ------------------------------------------------------------------

  /// 从文件导入字幕。返回一句话结果给 UI 提示；用户取消返回 null。
  Future<String?> importFromPicker() async {
    final mediaId = state.mediaId;
    if (mediaId == null) return null;
    try {
      final track = await _service.importFromPicker(mediaId);
      if (track == null) return null;
      await _reload(mediaId);
      return '已导入 ${state.lines.length} 句字幕';
    } catch (error) {
      state = state.copyWith(
        error: SubtitleService.asAppException(error).message,
      );
      return null;
    }
  }

  /// 手动新建一条字幕轨并立刻加一句（时间点取当前播放位置）。
  Future<String?> createManualTrackAndLine(int positionMs) async {
    final mediaId = state.mediaId;
    if (mediaId == null) return null;
    try {
      final track = await _service.createManualTrack(mediaId);
      final trackId = track.id;
      if (trackId == null) return null;
      await _service.addLine(
        mediaId: mediaId,
        trackId: trackId,
        startMs: positionMs,
        text: '',
      );
      await _reload(mediaId);
      return '已在 ${_formatMs(positionMs)} 处新建字幕';
    } catch (error) {
      state = state.copyWith(
        error: SubtitleService.asAppException(error).message,
      );
      return null;
    }
  }

  /// 在当前播放位置插入一句（已有激活字幕轨时用）。
  Future<String?> addSelectedSentence(int startMs, int endMs) async {
    final mediaId = state.mediaId;
    if (mediaId == null || startMs < 0 || endMs <= startMs) return null;
    try {
      SubtitleTrack? selected;
      for (final track in state.tracks) {
        if (track.source == SubtitleSource.manual && track.name == '手动断句') {
          selected = track;
          break;
        }
      }
      selected ??= await _service.createManualTrack(mediaId, name: '手动断句');
      final trackId = selected.id!;
      await _service.addLine(
        mediaId: mediaId,
        trackId: trackId,
        startMs: startMs,
        endMs: endMs,
      );
      await _service.toggleTrackExclusive(mediaId, trackId, true);
      await _reload(mediaId);
      return '已保存断句，按时间自动排序';
    } catch (error) {
      state = state.copyWith(
        error: SubtitleService.asAppException(error).message,
      );
      return null;
    }
  }

  Future<String?> addLineAt(int positionMs) async {
    final mediaId = state.mediaId;
    if (mediaId == null) return null;

    // 优先插到当前显示的那条轨上；一条都没有时新建一条手写轨
    int? trackId;
    for (final track in state.tracks) {
      if (track.isActive && track.id != null) {
        trackId = track.id;
        break;
      }
    }
    if (trackId == null) {
      return createManualTrackAndLine(positionMs);
    }

    try {
      await _service.addLine(
        mediaId: mediaId,
        trackId: trackId,
        startMs: positionMs,
        text: '',
      );
      await _reload(mediaId);
      return '已在 ${_formatMs(positionMs)} 处插入一句';
    } catch (error) {
      state = state.copyWith(
        error: SubtitleService.asAppException(error).message,
      );
      return null;
    }
  }

  // ------------------------------------------------------------------
  // 编辑
  // ------------------------------------------------------------------

  Future<bool> updateLine(SubtitleLine line) async {
    final mediaId = state.mediaId;
    try {
      await _service.updateLine(line);
      if (mediaId != null) await _reload(mediaId);
      return true;
    } catch (error) {
      state = state.copyWith(
        error: SubtitleService.asAppException(error).message,
      );
      return false;
    }
  }

  Future<void> deleteLine(int lineId) async {
    final mediaId = state.mediaId;
    int? trackId;
    for (final line in state.lines) {
      if (line.id == lineId) {
        trackId = line.trackId;
        break;
      }
    }
    if (trackId == null) return;
    try {
      await _service.deleteLine(trackId, lineId);
      if (mediaId != null) await _reload(mediaId);
    } catch (error) {
      state = state.copyWith(error: humanizeError(error));
    }
  }

  Future<void> deleteTrack(int trackId) async {
    final mediaId = state.mediaId;
    try {
      await _service.deleteTrack(trackId);
      if (mediaId != null) await _reload(mediaId);
    } catch (error) {
      state = state.copyWith(error: humanizeError(error));
    }
  }

  /// 切换某条轨是否显示（单语模式：独占激活）。
  Future<void> toggleTrackSingle(int trackId, bool active) async {
    final mediaId = state.mediaId;
    if (mediaId == null) return;
    try {
      await _service.toggleTrackExclusive(mediaId, trackId, active);
      await _reload(mediaId);
    } catch (error) {
      state = state.copyWith(error: humanizeError(error));
    }
  }

  /// 追加显示（双语同显）。
  Future<void> toggleTrackAppend(int trackId, bool active) async {
    final mediaId = state.mediaId;
    if (mediaId == null) return;
    try {
      await _service.setTrackActive(trackId, active);
      await _reload(mediaId);
    } catch (error) {
      state = state.copyWith(error: humanizeError(error));
    }
  }

  Future<void> clearTrack(int trackId) async {
    final mediaId = state.mediaId;
    try {
      await _service.clearTrack(trackId);
      if (mediaId != null) await _reload(mediaId);
    } catch (error) {
      state = state.copyWith(error: humanizeError(error));
    }
  }

  // ------------------------------------------------------------------
  // 整段语音识别与 AI 自动分句
  // ------------------------------------------------------------------

  /// 返回给 UI 展示的提示文案。
  Future<String> runAiTranscribe({
    required String mediaUri,
    required String mediaName,
  }) async {
    final mediaId = state.mediaId;
    if (mediaId == null) return '请先打开一个媒体文件';

    final generation = ++_transcriptionGeneration;
    final transcriber = _transcriber;
    state = state.copyWith(busyLabel: '正在识别…', busyProgress: 0);
    try {
      await _service.importFromTranscriber(
        mediaId: mediaId,
        mediaUri: mediaUri,
        mediaName: mediaName,
        transcriber: transcriber,
        onProgress: (ratio, message) {
          if (_transcriptionGeneration == generation &&
              state.mediaId == mediaId) {
            state = state.copyWith(busyLabel: message, busyProgress: ratio);
          }
        },
      );
      if (_transcriptionGeneration == generation && state.mediaId == mediaId) {
        await _reload(mediaId);
      }
      return 'AI 自动分句已生成';
    } catch (error) {
      final message = SubtitleService.asAppException(error).message;
      if (_transcriptionGeneration == generation && state.mediaId == mediaId) {
        state = state.copyWith(error: message);
      }
      return message;
    } finally {
      if (_transcriptionGeneration == generation && state.mediaId == mediaId) {
        state = state.copyWith(clearBusy: true);
      }
    }
  }

  // ------------------------------------------------------------------
  // 吸附（需求 §4.1）
  // ------------------------------------------------------------------

  /// 把时间点吸附到最近的字幕边界。关闭吸附或无字幕时原样返回。
  int snap(int valueMs, {required bool enabled}) {
    if (!enabled || state.cues.isEmpty) return valueMs;
    final result = SubtitleSnapper.snapWithDefaultThreshold(
      valueMs,
      state.cues,
    );
    return result.snapped ? result.valueMs : valueMs;
  }

  /// 判断吸附会不会发生，用于拖动时给用户一个「快贴上去了」的视觉提示。
  SnapResult previewSnap(int valueMs, {required bool enabled}) {
    if (!enabled || state.cues.isEmpty) {
      return SnapResult(valueMs: valueMs, snapped: false);
    }
    return SubtitleSnapper.snapWithDefaultThreshold(valueMs, state.cues);
  }

  /// 当前播放位置对应哪一句（用于高亮）。
  SubtitleCue? cueAt(int positionMs) =>
      SubtitleSnapper.cueAt(positionMs, state.cues);

  void consumeError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  static String _formatMs(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

final subtitleProvider = StateNotifierProvider<SubtitleNotifier, SubtitleState>(
  (ref) {
    final channel = ref.watch(nativeChannelProvider);
    final transcriber = WhisperTranscriber(
      channel: channel,
      readSettings: () => ref.read(settingsProvider),
      readApiKey: channel.readTranscriberApiKey,
    );
    return SubtitleNotifier(
      service: ref.watch(subtitleServiceProvider),
      transcriber: transcriber,
    );
  },
);
