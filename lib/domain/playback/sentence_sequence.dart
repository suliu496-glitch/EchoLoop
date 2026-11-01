/// Returns the next sentence, or null when sequential playback ends.
int? nextSentenceIndex(int current, int length, {required bool repeat}) {
  if (length <= 0 || current < 0 || current >= length) return null;
  if (current + 1 < length) return current + 1;
  return repeat ? 0 : null;
}
