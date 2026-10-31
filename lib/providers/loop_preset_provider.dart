import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dao/loop_preset_dao.dart';
import '../data/models/loop_preset.dart';
import 'core_providers.dart';

/// 片段收藏：把调好的 AB 片段存下来，下次一键载入。
class LoopPresetNotifier extends StateNotifier<List<LoopPreset>> {
  LoopPresetNotifier(this._dao) : super(const []);

  final LoopPresetDao _dao;

  int? _mediaId;

  Future<void> loadFor(int? mediaId) async {
    _mediaId = mediaId;
    if (mediaId == null) {
      state = const [];
      return;
    }
    state = await _dao.listOf(mediaId);
  }

  /// 收藏当前片段。[note] 是备注，留空时自动按时间命名。
  Future<void> add({
    required int startMs,
    required int endMs,
    String note = '',
  }) async {
    final mediaId = _mediaId;
    if (mediaId == null) return;
    await _dao.insert(
      LoopPreset(
        mediaId: mediaId,
        startMs: startMs,
        endMs: endMs,
        note: note.isEmpty ? _autoNote(startMs, endMs) : note,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    state = await _dao.listOf(mediaId);
  }

  Future<void> remove(int presetId) async {
    final mediaId = _mediaId;
    await _dao.delete(presetId);
    if (mediaId != null) state = await _dao.listOf(mediaId);
  }

  static String _autoNote(int startMs, int endMs) {
    String fmt(int ms) {
      final seconds = ms / 1000;
      final m = seconds ~/ 60;
      final s = (seconds % 60).toStringAsFixed(1);
      return '$m:${s.padLeft(4, '0')}';
    }

    return '${fmt(startMs)} → ${fmt(endMs)}';
  }
}

final loopPresetProvider =
    StateNotifierProvider<LoopPresetNotifier, List<LoopPreset>>((ref) {
  return LoopPresetNotifier(ref.watch(loopPresetDaoProvider));
});
