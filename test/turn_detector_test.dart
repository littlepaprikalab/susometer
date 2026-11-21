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
  int? _ranTo;

  /// Advances from where the last run stopped (or the detector's start) to
  /// [end] in 10 ms steps, running scripted actions and ticking every 100 ms.
  void run(int end) {
    final from = _ranTo == null ? detector.startMs : _ranTo! + 10;
    _ranTo = end;
    for (var t = from; t <= end; t += 10) {
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

TurnDetector party({TurnConfig config = const TurnConfig()}) =>
    TurnDetector(party: true, startMs: 0, config: config);

TurnDetector solo() => TurnDetector(party: false, startMs: 0);

void main() {
  group('question end: taps only (SPEC §7, decision 76)', () {
    test('silence, the player talking and room noise never end it', () {
      final s = Script(party());
      for (var t = 1000; t <= 2500; t += 300) {
        s.speech(t);
      }
      s.talk(4000, true);
      s.talk(6000, false);
      for (var t = 8000; t <= 9000; t += 100) {
        s.level(t, 0.9);
      }
      s.run(60000);
      expect(s.detector.questionEnded, isFalse);
      expect(s.events.whereType<QuestionEnded>(), isEmpty);
      expect(s.events.whereType<AnswerStarted>(), isEmpty);
      expect(s.events.whereType<AnswerEnded>(), isEmpty);
      // Talking after the asker is only noted, for the transcript.
      expect(s.events.whereType<EarlyAnswer>().length, 1);
    });

    test("Done asking ends it at the asker's last words", () {
      final s = Script(party());
      s.speech(1000);
      s.speech(1800);
      s.doneAsking(4000);
      s.talk(4500, true);
      s.run(5000);
      final q = s.first<QuestionEnded>()!;
      expect(q.reason, QuestionEndReason.button);
      expect(s.detector.tQ0, 1000);
      expect(q.tMs, 1800);
      expect(s.detector.tQ1, 1800);
      // The tap took 2.2 s: 1.5 s of it is allowed for tapping.
      expect(s.detector.hesitationFromMs, 3300);
      expect(s.detector.tA0, 4500);
      expect(s.first<AnswerStarted>()!.tMs, 4500);
    });

    test('a quick tap costs nothing', () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(1800);
      s.talk(2300, true);
      s.run(3000);
      expect(s.detector.tQ1, 1000);
      expect(s.detector.hesitationFromMs, 1800);
      expect(s.detector.tA0, 2300);
    });

    test("a slow tap can't hide a slow answer", () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(3000);
      s.talk(6000, true);
      s.run(7000);
      expect(s.detector.hesitationFromMs, 2500, reason: '1.5 s for the tap');
      expect(s.detector.tA0, 6000);
    });

    test('answering before the tap: the answer starts when they began', () {
      final s = Script(party());
      s.speech(1000);
      s.speech(1800);
      s.talk(2500, true);
      s.talk(4500, false);
      s.run(5900);
      expect(s.detector.questionEnded, isFalse);
      expect(s.detector.earlyTalkMs, 2500);
      s.doneAsking(6000);
      s.run(6500);
      expect(s.detector.tQ1, 1800);
      expect(s.detector.tA0, 2500);
      expect(s.first<AnswerStarted>()!.tMs, 2500);
    });

    test('a reaction the asker talks over is not the answer', () {
      final s = Script(party());
      s.speech(1000);
      s.talk(1500, true);
      s.talk(1900, false);
      s.speech(3500);
      s.speech(3800);
      s.doneAsking(4200);
      s.talk(5000, true);
      s.run(6000);
      expect(s.detector.tQ1, 3800);
      expect(s.detector.tA0, 5000);
    });

    test("words just after the player stops are theirs, not the asker's", () {
      final s = Script(party());
      s.speech(1000);
      s.talk(2000, true);
      s.talk(3000, false);
      // Recognition delivers the end of the player's sentence late.
      s.speech(3400);
      s.level(3500, 0.8);
      s.doneAsking(5000);
      s.run(5500);
      expect(s.detector.tQ1, 1000);
      expect(s.detector.tA0, 2000);
    });

    test('mic level extends the asker but never starts a question', () {
      final s = Script(party());
      s.speech(1000);
      for (var t = 1100; t <= 3000; t += 100) {
        s.level(t, 0.7);
      }
      s.doneAsking(5000);
      s.run(5500);
      expect(s.detector.tQ1, 3000);

      final noise = Script(party());
      for (var t = 1000; t <= 3000; t += 100) {
        noise.level(t, 0.9);
      }
      noise.doneAsking(5000);
      noise.run(5500);
      expect(noise.detector.lastAskerSpeechMs, isNull);
      expect(noise.detector.tQ1, 5000, reason: 'nothing heard: the tap');
    });

    test('a flickering talking flag never counts as a talk start', () {
      final s = Script(party());
      s.speech(1000);
      for (var t = 1200; t < 2000; t += 100) {
        s.talk(t, (t ~/ 100).isEven);
      }
      s.talk(2000, false);
      s.doneAsking(3000);
      s.run(3500);
      expect(s.detector.earlyTalkMs, isNull);
      expect(s.detector.tA0, isNull);
    });

    test('talking before the asker says anything is not an early answer', () {
      final s = Script(party());
      s.talk(500, true);
      s.talk(1500, false);
      s.speech(2600);
      s.doneAsking(3000);
      s.run(3500);
      expect(s.detector.tA0, isNull);
    });

    test('tapping Done asking while the player already talks starts the '
        'answer', () {
      final s = Script(party());
      s.talk(1000, true);
      s.doneAsking(1500);
      s.run(2000);
      expect(s.detector.tQ1, 1500);
      expect(s.detector.tA0, 1500);
    });
  });

  group('answer end: Final answer only (SPEC §7, decision 76)', () {
    test('silence never ends it, however long', () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(1500);
      s.talk(2000, true);
      s.talk(5000, false);
      s.run(60000);
      expect(s.detector.answerEnded, isFalse);
      expect(s.events.whereType<AnswerEnded>(), isEmpty);
    });

    test('Final answer soon after the last words: ends at the tap', () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(1500);
      s.talk(2000, true);
      s.talk(5000, false);
      s.finalAnswer(7000);
      s.run(7500);
      expect(s.detector.tA1, 7000);
      expect(s.first<AnswerEnded>()!.tMs, 7000);
    });

    test('a late Final answer: the scored answer ends 4 s after the last '
        'words', () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(1500);
      s.talk(2000, true);
      s.talk(5000, false);
      s.finalAnswer(20000);
      s.run(20500);
      expect(s.detector.tA1, 9000);
      expect(s.first<AnswerEnded>()!.tMs, 9000);
    });

    test('a pause mid-answer counts from the last words', () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(1500);
      s.talk(2000, true);
      s.talk(4000, false);
      s.talk(6500, true);
      s.talk(8000, false);
      s.finalAnswer(20000);
      s.run(20500);
      expect(s.detector.tA1, 12000);
    });

    test('room chatter after the player is done never stretches the answer '
        '(PR #18 review)', () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(1500);
      s.talk(2000, true);
      s.talk(5000, false);
      // The room chats from 15 s; nobody taps until 45 s.
      for (var t = 15000; t <= 40000; t += 500) {
        s.speech(t);
        s.level(t, 0.9);
      }
      s.finalAnswer(45000);
      s.run(45000);
      expect(s.detector.tA1, 9000, reason: '4 s after the player stopped');
    });

    test(
      'a pause over 4 s, then the player talks again: the answer goes on',
      () {
        final s = Script(party());
        s.speech(1000);
        s.doneAsking(1500);
        s.talk(2000, true);
        s.talk(4000, false);
        s.speech(12000); // chatter in the gap: not the player
        s.talk(14000, true); // the camera sees the player again
        s.talk(16000, false);
        s.finalAnswer(40000);
        s.run(40000);
        expect(s.detector.tA1, 20000);
      },
    );

    test('words keep the answer going if the talking flag drops out', () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(1500);
      s.talk(2000, true);
      s.talk(3000, false);
      for (var t = 3500; t <= 7000; t += 500) {
        s.speech(t);
      }
      s.finalAnswer(20000);
      s.run(20500);
      expect(s.detector.tA1, 11000);
    });

    test('still talking at the tap: ends at the tap', () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(1500);
      s.talk(2000, true);
      s.finalAnswer(30000);
      s.run(30500);
      expect(s.detector.tA1, 30000);
    });

    test('no answer heard: ends at the tap', () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(2000);
      s.finalAnswer(30000);
      s.run(30500);
      expect(s.detector.tA0, isNull);
      expect(s.detector.tA1, 30000);
    });

    test('a forgotten Final answer: at most 60 s after the question', () {
      final silent = Script(party());
      silent.speech(1000);
      silent.doneAsking(2000);
      silent.finalAnswer(30 * 60000);
      silent.run(30 * 60000);
      expect(silent.detector.tA1, 1000 + 60000);

      final stuck = Script(party());
      stuck.speech(1000);
      stuck.doneAsking(2000);
      stuck.talk(3000, true);
      stuck.finalAnswer(10 * 60000);
      stuck.run(10 * 60000);
      expect(stuck.detector.tA1, 1000 + 60000, reason: 'talking flag stuck on');

      final story = Script(party());
      story.speech(1000);
      story.doneAsking(2000);
      for (var t = 3000; t <= 90000; t += 1000) {
        story.talk(t, t % 2000 == 1000);
      }
      story.finalAnswer(95000);
      story.run(95000);
      expect(story.detector.tA1, 61000, reason: 'a long story is capped too');
    });

    test('an answer that only starts after the minute is scored as none', () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(2000);
      s.talk(90000, true);
      s.talk(93000, false);
      s.finalAnswer(94000);
      s.run(94000);
      final t = s.detector.timing();
      expect(t.tA1, 61000);
      expect(t.tA0, isNull, reason: 'it started after the scored answer');
      expect(t.windowEnd(12000) - t.tQ0, lessThanOrEqualTo(60000));
    });

    test('the scored question starts at most 60 s before it ended', () {
      final s = Script(party());
      for (var t = 1000; t <= 600000; t += 1000) {
        s.speech(t);
      }
      s.doneAsking(601000);
      s.talk(601500, true);
      s.talk(603000, false);
      s.finalAnswer(604000);
      s.run(604000);
      final t = s.detector.timing();
      expect(s.detector.tQ0, 1000, reason: 'the detector keeps the real start');
      expect(t.tQ1, 600000);
      expect(t.tQ0, 600000 - 60000);
      expect(t.tA0, 601500);
    });

    test('Final answer straight from Ask ends the question too', () {
      final s = Script(party());
      s.speech(1000);
      s.finalAnswer(1500);
      s.run(2000);
      expect(s.first<QuestionEnded>()!.reason, QuestionEndReason.button);
      expect(s.detector.tQ1, 1000);
      expect(s.detector.tA1, 1500);
      expect(s.detector.tA0, isNull);
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
    test('hesitation counts from the tap to the first talk', () {
      final s = Script(party());
      s.doneAsking(5000);
      s.talk(6000, true);
      s.talk(7000, false);
      s.run(19990);
      expect(s.detector.hesitationFromMs, 5000);
      expect(s.detector.tA0, 6000);
      expect(s.detector.answerEnded, isFalse);
      s.finalAnswer(20000);
      s.run(20100);
      expect(s.detector.answerEnded, isTrue);
    });
  });

  group('solo mode', () {
    test('the host reading defines the question window', () {
      final s = Script(solo());
      expect(s.detector.tQ0, 0);
      s.hostDone(4000);
      s.talk(5200, true);
      s.talk(7000, false);
      s.finalAnswer(9000);
      s.run(12000);
      expect(s.first<QuestionEnded>()!.reason, QuestionEndReason.hostDone);
      expect(s.detector.tQ1, 4000);
      expect(s.detector.tA0, 5200);
      expect(s.detector.tA1, 9000);
    });

    test('talking over the host: the answer starts when the host finishes', () {
      final s = Script(solo());
      s.talk(2000, true);
      s.run(3900);
      expect(s.detector.questionEnded, isFalse);
      s.hostDone(4000);
      s.run(4500);
      expect(s.detector.tQ1, 4000);
      expect(s.detector.tA0, 4000);
    });

    test('Ready to answer after the host: up to 1.5 s for the tap', () {
      final quick = Script(solo());
      quick.hostDone(4000);
      quick.run(4800);
      quick.detector.onReadyTap(4800);
      quick.talk(5300, true);
      quick.run(6000);
      expect(quick.detector.tQ1, 4000);
      expect(quick.detector.hesitationFromMs, 4800);
      expect(quick.detector.tA0, 5300);

      final slow = Script(solo());
      slow.hostDone(4000);
      slow.run(9000);
      slow.detector.onReadyTap(9000);
      expect(slow.detector.hesitationFromMs, 5500);

      final answering = Script(solo());
      answering.hostDone(4000);
      answering.talk(4500, true);
      answering.run(6000);
      answering.detector.onReadyTap(6000);
      expect(
        answering.detector.hesitationFromMs,
        4000,
        reason: 'already answering: the tap changes nothing',
      );
    });

    test('Ready to answer while the host reads ends the question there', () {
      final s = Script(solo());
      s.speech(1000);
      s.doneAsking(3000);
      s.run(3500);
      expect(s.detector.lastAskerSpeechMs, isNull, reason: 'no asker');
      expect(s.detector.tQ1, 3000);
    });
  });

  group('solo: words start the answer when the camera misses it', () {
    test('heard with no talking flag: the answer starts 1 s before the '
        'first words arrived, not at the Final answer tap', () {
      final s = Script(solo());
      s.hostDone(4000);
      s.speech(6500);
      s.speech(7300);
      s.finalAnswer(9000);
      s.run(9500);
      final t = s.detector.timing();
      expect(t.tA0, 5500);
      expect(s.detector.answerStartFromWords, isTrue);
      expect(s.first<AnswerStarted>()!.tMs, 5500);
      expect(t.tA0! - t.hesitationFromMs, 1500, reason: 'the pause');
      expect(t.tA1, 9000);
    });

    test('never before the question ended', () {
      final s = Script(solo());
      s.hostDone(4000);
      s.speech(4400);
      s.run(5000);
      expect(s.detector.tA0, 4000);
    });

    test('a talk start the camera dates earlier replaces the words', () {
      final s = Script(solo());
      s.hostDone(4000);
      s.speech(6500);
      // The camera's edge for 5 s arrives late, in a batch after the words.
      s.at(6600, (d) => d.onPlayerTalkEdge(true, 5000));
      s.run(7000);
      expect(s.detector.tA0, 5000);
      expect(s.detector.answerStartFromWords, isFalse);
      expect(s.events.whereType<AnswerStarted>().map((e) => e.tMs), [
        5500,
        5000,
      ]);
    });

    test('a talk start dated later keeps the earlier words', () {
      final s = Script(solo());
      s.hostDone(4000);
      s.speech(6500);
      s.talk(6600, true);
      s.run(7500);
      expect(s.detector.tA0, 5500);
      expect(s.detector.answerStartFromWords, isTrue);
      expect(s.events.whereType<AnswerStarted>().length, 1);
    });

    test('a talking flag already up: the words wait for its start', () {
      final s = Script(solo());
      s.hostDone(4000);
      s.talk(5000, true);
      s.speech(5100); // before the 200 ms debounce confirms the talk
      s.run(6000);
      expect(s.detector.tA0, 5000);
      expect(s.detector.answerStartFromWords, isFalse);
    });

    test('the camera seeing it first: words change nothing', () {
      final s = Script(solo());
      s.hostDone(4000);
      s.talk(5200, true);
      s.talk(6500, false);
      s.speech(7000);
      s.run(8000);
      expect(s.detector.tA0, 5200);
      expect(s.detector.answerStartFromWords, isFalse);
    });

    test('words after the minute: still scored as no answer', () {
      final s = Script(solo());
      s.hostDone(4000);
      s.speech(90000);
      s.finalAnswer(95000);
      s.run(95000);
      final t = s.detector.timing();
      expect(t.tA1, 64000);
      expect(t.tA0, isNull);
    });

    test('party: words alone never start the answer (they may be the '
        "room's)", () {
      final s = Script(party());
      s.speech(1000);
      s.doneAsking(2000);
      s.speech(4000);
      s.finalAnswer(9000);
      s.run(9500);
      expect(s.detector.tA0, isNull);
      expect(s.detector.answerStartFromWords, isFalse);
      expect(s.detector.tA1, 9000);
    });
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
