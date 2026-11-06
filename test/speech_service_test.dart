import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/voice/speech_service.dart';

void main() {
  group('SpeechEvent.fromMap', () {
    test('partial and final text', () {
      final p = SpeechEvent.fromMap({
        'type': 'partial',
        'text': 'have you ever',
        'seg': 1,
        't': 10,
      });
      expect(p, isA<SpeechText>());
      expect((p! as SpeechText).isFinal, isFalse);
      expect(p.tMs, 10);

      final f = SpeechEvent.fromMap({
        'type': 'final',
        'text': 'Have you ever lied?',
        'seg': 1,
        't': 20,
      });
      expect((f! as SpeechText).isFinal, isTrue);
    });

    test('level, state and error', () {
      expect(
        (SpeechEvent.fromMap({'type': 'level', 'level': 0.4, 't': 1})!
                as SpeechLevel)
            .level,
        0.4,
      );
      expect(
        (SpeechEvent.fromMap({'type': 'state', 'state': 'paused', 't': 1})!
                as SpeechStateChange)
            .state,
        'paused',
      );
      final e =
          SpeechEvent.fromMap({
                'type': 'error',
                'code': 'ON_DEVICE_UNAVAILABLE',
                'message': 'nope',
                't': 1,
              })!
              as SpeechError;
      expect(e.code, 'ON_DEVICE_UNAVAILABLE');
    });

    test('drops malformed or unknown events', () {
      expect(SpeechEvent.fromMap({'type': 'partial', 't': 1}), isNull);
      expect(SpeechEvent.fromMap({'type': 'mystery'}), isNull);
    });
  });

  group('TranscriptBuffer', () {
    SpeechText text(String t, int seg, {bool fin = false, int at = 0}) =>
        SpeechText(text: t, segment: seg, isFinal: fin, tMs: at);

    test('partials replace each other within a segment', () {
      final b = TranscriptBuffer()
        ..add(text('have', 1, at: 1))
        ..add(text('have you', 1, at: 2))
        ..add(text('Have you ever lied?', 1, fin: true, at: 3));
      expect(b.text, 'Have you ever lied?');
      expect(b.lastUpdateMs, 3);
    });

    test('segments join in order, even if events arrive out of order', () {
      final b = TranscriptBuffer()
        ..add(text('second part', 2))
        ..add(text('First part.', 1, fin: true));
      expect(b.text, 'First part. second part');
      expect(b.latestSegment, 'First part.');
    });

    test('ignores blank text and clears', () {
      final b = TranscriptBuffer()..add(text('   ', 1));
      expect(b.isEmpty, isTrue);
      b
        ..add(text('hello', 1))
        ..clear();
      expect(b.isEmpty, isTrue);
      expect(b.text, '');
      expect(b.lastUpdateMs, isNull);
    });
  });
}
