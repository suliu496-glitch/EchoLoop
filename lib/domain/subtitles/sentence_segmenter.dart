import '../../services/transcriber/transcriber.dart';

/// Turns timestamped ASR words into sentence-sized listening cues.
/// Punctuation is the primary boundary; a long acoustic pause is a fallback.
class SentenceSegmenter {
  const SentenceSegmenter({
    this.minimumSentenceMs = 1500,
    this.maximumSentenceMs = 12000,
    this.pauseBoundaryMs = 650,
    this.tailPaddingMs = 200,
  });

  final int minimumSentenceMs;
  final int maximumSentenceMs;
  final int pauseBoundaryMs;
  final int tailPaddingMs;

  List<TranscriptSegment> segment(
    List<TranscriptSegment> timedWords, {
    int? mediaDurationMs,
  }) {
    final words =
        timedWords
            .where(
              (word) =>
                  word.endMs > word.startMs && word.text.trim().isNotEmpty,
            )
            .toList()
          ..sort((a, b) => a.startMs.compareTo(b.startMs));
    if (words.isEmpty) return const [];

    final groups = <List<TranscriptSegment>>[];
    var current = <TranscriptSegment>[];

    void finishCurrent() {
      if (current.isNotEmpty) groups.add(current);
      current = <TranscriptSegment>[];
    }

    for (final word in words) {
      if (current.isNotEmpty) {
        final previous = current.last;
        final gapMs = word.startMs - previous.endMs;
        final wouldExceedMaximum =
            word.endMs - current.first.startMs > maximumSentenceMs;
        if (_endsSentence(previous.text) ||
            gapMs >= pauseBoundaryMs ||
            wouldExceedMaximum) {
          finishCurrent();
        }
      }
      current.add(word);
    }
    finishCurrent();

    final merged = _mergeShortGroups(groups);
    final result = <TranscriptSegment>[];
    for (var i = 0; i < merged.length; i++) {
      final group = merged[i];
      var startMs = group.first.startMs < 0 ? 0 : group.first.startMs;
      if (mediaDurationMs != null) {
        startMs = startMs.clamp(0, mediaDurationMs).toInt();
      }
      var endMs = group.last.endMs + tailPaddingMs;
      if (mediaDurationMs != null) {
        endMs = endMs.clamp(0, mediaDurationMs).toInt();
      }
      if (i + 1 < merged.length) {
        endMs = endMs.clamp(0, merged[i + 1].first.startMs).toInt();
      }
      if (endMs <= startMs) endMs = group.last.endMs;
      if (mediaDurationMs != null) {
        endMs = endMs.clamp(0, mediaDurationMs).toInt();
      }
      final text = group
          .map((word) => word.text)
          .join()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isEmpty || endMs <= startMs) continue;
      result.add(TranscriptSegment(startMs: startMs, endMs: endMs, text: text));
    }
    return result;
  }

  /// Some compatible services return phrase timestamps instead of word times.
  /// Split multiple punctuated sentences proportionally within each phrase.
  List<TranscriptSegment> splitPhrases(
    List<TranscriptSegment> phrases, {
    int? mediaDurationMs,
  }) {
    final candidates = <TranscriptSegment>[];
    for (final phrase in phrases) {
      final text = phrase.text.trim();
      if (text.isEmpty || phrase.endMs <= phrase.startMs) continue;
      final parts = _splitText(text);
      if (parts.length == 1) {
        candidates.add(phrase);
        continue;
      }

      final weights = parts
          .map((part) => part.replaceAll(RegExp(r'\s+'), '').length)
          .toList();
      final totalWeight = weights.fold<int>(0, (sum, value) => sum + value);
      var cursor = phrase.startMs;
      var usedWeight = 0;
      for (var i = 0; i < parts.length; i++) {
        usedWeight += weights[i];
        final end = i == parts.length - 1
            ? phrase.endMs
            : phrase.startMs +
                  ((phrase.endMs - phrase.startMs) * usedWeight / totalWeight)
                      .round();
        candidates.add(
          TranscriptSegment(
            startMs: cursor,
            endMs: end,
            text: parts[i],
            confidence: phrase.confidence,
          ),
        );
        cursor = end;
      }
    }
    return segment(candidates, mediaDurationMs: mediaDurationMs);
  }

  List<List<TranscriptSegment>> _mergeShortGroups(
    List<List<TranscriptSegment>> groups,
  ) {
    final result = <List<TranscriptSegment>>[];
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      final duration = group.last.endMs - group.first.startMs;
      if (duration >= minimumSentenceMs ||
          groups.length == 1 ||
          _endsSentence(group.last.text)) {
        result.add(group);
        continue;
      }

      if (i + 1 < groups.length) {
        result.add([...group, ...groups[++i]]);
      } else if (result.isNotEmpty) {
        result.last.addAll(group);
      } else {
        result.add(group);
      }
    }
    return result;
  }

  static bool _endsSentence(String text) =>
      RegExp(r'[.!?。！？…]["”’\)\]]*\s*$').hasMatch(text.trim());

  static List<String> _splitText(String text) {
    final parts = <String>[];
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final character = String.fromCharCode(rune);
      buffer.write(character);
      if ('.!?。！？…'.contains(character)) {
        final value = buffer.toString().trim();
        if (value.isNotEmpty) parts.add(value);
        buffer.clear();
      }
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts.isEmpty ? [text] : parts;
  }
}
