import 'package:flutter_test/flutter_test.dart';
import 'package:echoloop/data/models/app_settings.dart';
import 'package:echoloop/domain/playback/sentence_sequence.dart';

void main() {
  test('sequential playback stops at the last sentence', () {
    expect(nextSentenceIndex(0, 3, repeat: false), 1);
    expect(nextSentenceIndex(2, 3, repeat: false), isNull);
  });

  test('list repeat wraps, including a list with one sentence', () {
    expect(nextSentenceIndex(2, 3, repeat: true), 0);
    expect(nextSentenceIndex(0, 1, repeat: true), 0);
    expect(nextSentenceIndex(0, 0, repeat: true), isNull);
    expect(nextSentenceIndex(-1, 3, repeat: true), isNull);
  });

  test('list repeat setting survives persistence and defaults to off', () {
    expect(AppSettings.fromValues({}).repeatSentenceList, isFalse);
    final values = const AppSettings(repeatSentenceList: true).toValues();
    expect(AppSettings.fromValues(values).repeatSentenceList, isTrue);
  });
}
