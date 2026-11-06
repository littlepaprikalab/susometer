import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/voice/turn_detector.dart';

/// Runs a scripted stream through a detector with 100 ms ticks and collects
/// the events. Script entries are (time, action).
class Script {
  Script(this.detector);

  final TurnDetector detector;
  final List<TurnEvent> events = [];
  final Map<int, List<void Function()>> _at = {};

  void at(int t, void Function(TurnDetector d) action) =>
      (_at[t] ??= []).add(() => events.addAll(_wrap(action)));

  List<TurnEvent> _wrap(void Function(TurnDetector d) action) {
    final before = <TurnEvent>[];
    action(detector);
    return before;
  }

  void talk(int t, bool on) => (_at[t] ??= []).add(
    () => events.addAll(detector.onPlayerTalkEdge(on, t)),
  );
  void speech(int t) =>
      (_at[t] ??= []).add(() => events.addAll(detector.onSpeech(t)));
  void level(int t, double v) =>
      (_at[t] ??= []).add(() => events.addAll(detector.onLevel(v, t)));
  void doneAsking(int t) =>
      (_at[t] ??= []).add(() => events.addAll(detector.onDoneAskingTap(t)));
  void finalAnswer(int t) =>
      (_at[t] ??= []).add(() => events.addAll(detector.onFinalAnswerTap(t)));
  void hostDone(int t) => (_at[t] ??= []).add(
    () => events.addAll(detector.onHostFinishedQuestion(t)),
  );
  void promptDone(int t) =>
      (_at[t] ??= []).add(() => detector.onHostPromptFinished(t));

  /// Advances from the detector's start to [end] in 10 ms steps, running
  /// scripted actions and ticking every 100 ms.
  void run(int end) {
    for (var t = detector.startMs; t <= end; t += 10) {
      for (final a in _at[t] ?? const <void Function()>[]) {
        a();
      }
      if (t % 100 == 0) events.addAll(detector.tick(t));
    }
  }

  T? first<T extends TurnEvent>() {
    for (final e in events) {
      if (e is T) return e;
    }
    return null;
  }
}

TurnDetector party({bool mic = true, TurnConfig config = const TurnConfig()}) =>
    TurnDetector(party: true, micEnabled: mic, startMs: 0, config: config);

void main() {
  group('question end (SPEC §7)', () {
    test(
      '1.5 s of silence after the asker ends the question; host prompts',
      () {
        final s = Script(party());
        for (var t = 1000; t <= 2500; t += 300) {
          s.speech(t);
        }
        s.run(6000);
        final q = s.first<QuestionEnded>()!;
        expect(q.reason, QuestionEndReason.askerSilence);
        expect(q.hostShouldPrompt, isTrue);
        expect(s.detector.tQ0, 1000);
        expect(q.tMs, greaterThanOrEqualTo(2500 + 1500));
        expect(q.tMs, lessThanOrEqualTo(2500 + 1600));
      },
    );

    test('the player starting to talk ends the question at once', () {
      final s = Script(party());
      s.speech(1000);
      s.speech(1800);
      s.talk(2100, true);
      s.run(4000);
      final q = s.first<QuestionEnded>()!;
      expect(q.reason, QuestionEndReason.playerTalk);
      expect(q.hostShouldPrompt, isFalse);
      expect(
        s.detector.tQ1,
        2100,
        reason: 'the edge time, not the debounce time',
      );
      expect(s.detector.tA0, 2100);
      expect(s.first<AnswerStarted>()!.tMs, 2100);
    });

    test('talking before the asker says anything is ignored', () {
      final s = Script(party());
      s.talk(500, true);
      s.talk(1500, false);
      s.run(6000);
      expect(s.detector.questionEnded, isFalse);
    });

    test('a flickering talking flag never counts as a talk start', () {
      final s = Script(party());
      s.speech(1000);
      for (var t = 1200; t < 2000; t += 100) {
        s.talk(t, (t ~/ 100).isEven);
      }
      s.talk(2000, false);
      // Asker keeps talking so silence can't end the question either.
      for (var t = 1300; t <= 2600; t += 300) {
        s.speech(t);
      }
      s.run(2700);
      expect(s.detector.questionEnded, isFalse);
    });

    test('mic level keeps an ongoing question open but cannot start one', () {
      final s = Script(party());
      s.speech(1000);
      for (var t = 1100; t <= 3000; t += 100) {
        s.level(t, 0.7);
      }
      s.run(6000);
      expect(s.first<QuestionEnded>()!.tMs, greaterThanOrEqualTo(4500));

      final noise = Script(party());
      for (var t = 1000; t <= 3000; t += 100) {
        noise.level(t, 0.9);
      }
      noise.run(8000);
      expect(
        noise.detector.questionEnded,
        isFalse,
        reason: 'noise alone never starts a question',
      );
    });

    test('backup button ends the question; no host prompt', () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(1400);
      s.run(2000);
      final q = s.first<QuestionEnded>()!;
      expect(q.reason, QuestionEndReason.button);
      expect(q.hostShouldPrompt, isFalse);
      expect(s.detector.hesitationFromMs, 1400);
    });

    test(
      'tapping Done asking while the player already talks starts the answer',
      () {
        final s = Script(party(mic: false));
        s.talk(1000, true);
        s.doneAsking(1500);
        s.run(2000);
        expect(s.detector.tA0, 1500);
      },
    );

    test('after the host prompt, hesitation counts from the prompt end', () {
      final s = Script(party());
      s.speech(1000);
      s.promptDone(4200);
      s.talk(5000, true);
      s.run(6000);
      expect(s.first<QuestionEnded>()!.reason, QuestionEndReason.askerSilence);
      expect(s.detector.hesitationFromMs, 4200);
      expect(s.detector.tA0, 5000);
      final timing = s.detector.timing();
      expect(timing.hesitationFromMs, 4200);
      expect(timing.tQ1, s.detector.tQ1);
    });
  });

  group('answer end (SPEC §7)', () {
    test('4 s of silence after the player last talked ends the answer', () {
      final s = Script(party());
      s.speech(1000);
      s.talk(2000, true);
      s.talk(5000, false);
      s.run(12000);
      final a = s.first<AnswerEnded>()!;
      expect(a.reason, AnswerEndReason.silence);
      expect(a.tMs, greaterThanOrEqualTo(9000));
      expect(a.tMs, lessThanOrEqualTo(9100));
    });

    test('a short pause mid-answer does not end it', () {
      final s = Script(party());
      s.speech(1000);
      s.talk(2000, true);
      s.talk(4000, false);
      s.talk(6500, true);
      s.talk(8000, false);
      s.run(11000);
      expect(s.detector.answerEnded, isFalse);
      s.run(13000);
      expect(s.first<AnswerEnded>()!.tMs, greaterThanOrEqualTo(12000));
    });

    test('words keep the answer open if the talking flag drops out', () {
      final s = Script(party());
      s.speech(1000);
      s.talk(2000, true);
      s.talk(3000, false);
      for (var t = 3500; t <= 7000; t += 500) {
        s.speech(t);
      }
      s.run(10500);
      expect(s.detector.answerEnded, isFalse);
      s.run(11100);
      expect(s.detector.answerEnded, isTrue);
    });

    test('Final answer ends it immediately (and the question, if needed)', () {
      final s = Script(party());
      s.speech(1000);
      s.finalAnswer(1500);
      s.run(2000);
      expect(s.first<QuestionEnded>()!.reason, QuestionEndReason.button);
      expect(s.first<AnswerEnded>()!.reason, AnswerEndReason.finalAnswer);
      expect(s.detector.tA1, 1500);
      expect(s.detector.tA0, isNull);
    });

    test('no answer at all ends after the no-answer timeout', () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(2000);
      s.run(25000);
      final a = s.first<AnswerEnded>()!;
      expect(a.reason, AnswerEndReason.noAnswer);
      expect(a.tMs, 22000);
    });

    test('events after the answer ended are ignored', () {
      final s = Script(party());
      s.speech(1000);
      s.finalAnswer(1500);
      s.talk(2000, true);
      s.speech(2500);
      s.run(9000);
      expect(s.events.whereType<AnswerEnded>().length, 1);
      expect(s.events.whereType<AnswerStarted>(), isEmpty);
    });
  });

  group('no-mic mode (SPEC §7)', () {
    test('only taps move things along', () {
      final s = Script(party(mic: false));
      s.speech(1000);
      s.run(5000);
      expect(s.detector.questionEnded, isFalse, reason: 'no silence detection');
      s.doneAsking(5000);
      s.talk(6000, true);
      s.talk(7000, false);
      s.run(20000);
      expect(
        s.detector.tA0,
        6000,
        reason: 'hesitation from the tap to talkStart',
      );
      expect(s.detector.answerEnded, isFalse, reason: 'no silence auto-end');
      s.finalAnswer(20000);
      s.run(20100);
      expect(s.detector.answerEnded, isTrue);
    });
  });

  group('solo mode', () {
    test('the host reading defines the question window', () {
      final s = Script(
        TurnDetector(party: false, micEnabled: true, startMs: 0),
      );
      expect(s.detector.tQ0, 0);
      s.hostDone(4000);
      s.talk(5200, true);
      s.talk(7000, false);
      s.run(12000);
      expect(s.first<QuestionEnded>()!.reason, QuestionEndReason.hostDone);
      expect(s.detector.tQ1, 4000);
      expect(s.detector.tA0, 5200);
      expect(s.first<AnswerEnded>()!.reason, AnswerEndReason.silence);
    });

    test('answering before the host finishes ends the question early', () {
      final s = Script(
        TurnDetector(party: false, micEnabled: true, startMs: 0),
      );
      s.talk(2000, true);
      s.hostDone(4000);
      s.run(4500);
      expect(s.first<QuestionEnded>()!.reason, QuestionEndReason.playerTalk);
      expect(s.detector.tQ1, 2000);
    });
  });

  test('tap-to-advance config switches the automatic rules off', () {
    final s = Script(
      party(
        config: const TurnConfig(autoQuestionEnd: false, autoAnswerEnd: false),
      ),
    );
    s.speech(1000);
    s.talk(2000, true);
    s.talk(3000, false);
    s.run(15000);
    expect(s.detector.questionEnded, isFalse);
    s.doneAsking(15000);
    s.talk(16000, true);
    s.talk(17000, false);
    s.run(30000);
    expect(s.detector.answerEnded, isFalse);
  });

  group('TalkTracker', () {
    test(
      'confirms starts after 200 ms and ends after 500 ms, at edge times',
      () {
        final t = TalkTracker(const TurnConfig());
        expect(t.edge(true, 1000), isEmpty);
        expect(t.settle(1150), isEmpty);
        expect(t.settle(1200), [(true, 1000)]);
        expect(t.talking, isTrue);
        expect(t.edge(false, 2000), isEmpty);
        expect(t.settle(2400), isEmpty);
        expect(t.settle(2500), [(false, 2000)]);
        expect(t.lastEndMs, 2000);
      },
    );

    test('repeated identical edges are ignored', () {
      final t = TalkTracker(const TurnConfig());
      t.edge(true, 1000);
      t.edge(true, 1100);
      expect(t.settle(1200), [(true, 1000)]);
    });
  });
}
