import 'dart:math' as math;

import '../game/models.dart';

/// Turn-detection constants (SPEC.md §7).
class TurnConfig {
  const TurnConfig({
    this.talkStartDebounceMs = 200,
    this.talkEndDebounceMs = 500,
    this.speechLevelThreshold = 0.45,
    this.answerTailMs = 4000,
    this.lateWordsMs = 1000,
    this.tapAllowanceMs = 1500,
    this.maxAnswerMs = 60000,
  });

  /// SmartSpectra `talking` must hold this long to count as a talk start.
  final int talkStartDebounceMs;

  /// ...and be off this long to count as a talk end.
  final int talkEndDebounceMs;

  /// Mic level (0..1) that counts as someone still speaking.
  final double speechLevelThreshold;

  /// When Final answer comes later than this after the player last spoke,
  /// the scored answer ends here instead, so the room's chatter while
  /// nobody tapped isn't read as part of it.
  final int answerTailMs;

  /// Words heard this soon after the player stops talking are taken as
  /// theirs, arriving late from recognition, not as the asker's.
  final int lateWordsMs;

  /// A tap before answering (Done asking, solo's Ready to answer) takes a
  /// moment, and the warm-ups the pause is compared with have none, so up
  /// to this much of the wait before the tap doesn't count as hesitation.
  /// Stalling longer than that before tapping does.
  final int tapAllowanceMs;

  /// The scored answer ends at most this long after the question did, however
  /// late Final answer comes. Nothing ends the answer on screen, so without
  /// it a forgotten tap would score (and search for heartbeats in) every
  /// minute since the question, freezing the screen on the tap.
  final int maxAnswerMs;
}

/// Debounces SmartSpectra `talking` edges into confirmed talk starts/ends.
/// Confirmed times are the raw edge times, not the confirmation times.
class TalkTracker {
  TalkTracker(this.config);

  final TurnConfig config;

  bool _raw = false;
  int? _rawAt;
  bool talking = false;
  int? lastStartMs;
  int? lastEndMs;

  /// Feed a raw edge. Returns any confirmed transitions.
  List<(bool, int)> edge(bool talkingNow, int tMs) {
    final out = <(bool, int)>[];
    if (talkingNow == _raw) return out;
    _raw = talkingNow;
    _rawAt = tMs;
    return out..addAll(settle(tMs));
  }

  /// Confirms pending edges once their debounce has passed.
  List<(bool, int)> settle(int nowMs) {
    final at = _rawAt;
    if (at == null) return const [];
    if (_raw && !talking && nowMs - at >= config.talkStartDebounceMs) {
      talking = true;
      lastStartMs = at;
      return [(true, at)];
    }
    if (!_raw && talking && nowMs - at >= config.talkEndDebounceMs) {
      talking = false;
      lastEndMs = at;
      return [(false, at)];
    }
    return const [];
  }

  /// Raw state, before debouncing.
  bool get rawTalking => _raw;

  void reset() {
    _raw = false;
    _rawAt = null;
    talking = false;
    lastStartMs = null;
    lastEndMs = null;
  }
}

/// What ended the question: Done asking (party, or solo's Ready to answer
/// while the host reads), Final answer straight from Ask, or the host
/// finishing the question (solo).
enum QuestionEndReason { button, hostDone }

sealed class TurnEvent {
  const TurnEvent(this.tMs);

  final int tMs;
}

class QuestionEnded extends TurnEvent {
  const QuestionEnded(this.reason, super.tMs);

  final QuestionEndReason reason;
}

class AnswerStarted extends TurnEvent {
  const AnswerStarted(super.tMs);
}

/// Final answer was tapped. [tMs] is where the scored answer ends, which
/// can be before the tap (see [TurnConfig.answerTailMs]).
class AnswerEnded extends TurnEvent {
  const AnswerEnded(super.tMs);
}

/// Marks the question's end (tQ1) and the answer's (tA1) for one question
/// (SPEC.md §7). Pure: feed it events, taps and clock ticks, read the events
/// back.
///
/// Nothing ends by itself: only Done asking (or, in solo mode, the host
/// finishing the question) ends the question, and only Final answer ends the
/// answer (SPEC.md decision 76). The voice and the camera still say *when*
/// things happened, so the score is timed from what was said, not from when
/// someone got round to tapping.
///
/// Speaker separation without diarization: mic speech while the player is
/// not talking (per SmartSpectra) is the asker; while talking, the answer.
class TurnDetector {
  TurnDetector({
    required this.party,
    required this.startMs,
    this.config = const TurnConfig(),
  }) : _talk = TalkTracker(config) {
    // Solo: the question starts when the host starts reading.
    if (!party) tQ0 = startMs;
  }

  final bool party;
  final int startMs;
  final TurnConfig config;
  final TalkTracker _talk;

  int? tQ0;
  int? tQ1;
  int? tA0;
  int? tA1;
  int? hesitationFromMs;
  QuestionEndReason? questionEndReason;
  int? lastAskerSpeechMs;
  int? lastPlayerActivityMs;

  /// Party: the player started talking after the asker's last words, before
  /// Done asking was tapped. If the asker carries on, it was a reaction, not
  /// the answer, and it's forgotten.
  int? earlyTalkMs;

  bool get questionEnded => tQ1 != null;
  bool get answerEnded => tA1 != null;
  bool get playerTalking => _talk.talking;

  /// A raw SmartSpectra talking edge.
  List<TurnEvent> onPlayerTalkEdge(bool talking, int tMs) =>
      _confirm(_talk.edge(talking, tMs));

  /// Whether speech at [tMs] can be the asker's: the player isn't talking
  /// and didn't only just stop (recognition delivers words late).
  bool _askerCouldSpeak(int tMs) {
    if (!party || _talk.talking || _talk.rawTalking) return false;
    final end = _talk.lastEndMs;
    return end == null || tMs - end >= config.lateWordsMs;
  }

  /// Recognized speech (new partial text) at [tMs].
  List<TurnEvent> onSpeech(int tMs) {
    if (answerEnded) return const [];
    if (!questionEnded) {
      if (_askerCouldSpeak(tMs)) {
        tQ0 ??= tMs;
        lastAskerSpeechMs = tMs;
        earlyTalkMs = null;
      }
    } else if (_talk.talking || _talk.rawTalking || tA0 != null) {
      // Once the player has started answering, new words keep the answer
      // open even if SmartSpectra's talking flag drops out for a moment.
      lastPlayerActivityMs = math.max(lastPlayerActivityMs ?? 0, tMs);
    }
    return const [];
  }

  /// Mic level. Only extends speech that recognition already picked up, so
  /// room noise alone can't start a question.
  List<TurnEvent> onLevel(double level, int tMs) {
    if (level < config.speechLevelThreshold || answerEnded) return const [];
    if (!questionEnded) {
      if (tQ0 != null &&
          lastAskerSpeechMs != null &&
          earlyTalkMs == null &&
          _askerCouldSpeak(tMs)) {
        lastAskerSpeechMs = tMs;
      }
    } else if (_talk.talking) {
      lastPlayerActivityMs = math.max(lastPlayerActivityMs ?? 0, tMs);
    }
    return const [];
  }

  /// "Done asking" (party), or solo's "Ready to answer" while the host is
  /// still reading.
  List<TurnEvent> onDoneAskingTap(int tMs) {
    if (questionEnded) return const [];
    return _endQuestion(QuestionEndReason.button, tMs);
  }

  /// Solo mode: the host finished reading the question.
  List<TurnEvent> onHostFinishedQuestion(int tMs) {
    if (questionEnded) return const [];
    return _endQuestion(QuestionEndReason.hostDone, tMs);
  }

  /// Solo "Ready to answer" after the host finished: it doesn't end
  /// anything, but like Done asking, the tap isn't counted as hesitation
  /// (see [TurnConfig.tapAllowanceMs]).
  void onReadyTap(int tMs) {
    if (!questionEnded || tA0 != null || answerEnded) return;
    hesitationFromMs = _pauseFrom(tQ1!, tMs);
  }

  /// Where hesitation counts from when the question ended at [endMs] and the
  /// player tapped at [tapMs] before answering.
  int _pauseFrom(int endMs, int tapMs) =>
      math.max(endMs, math.min(tapMs, endMs + config.tapAllowanceMs));

  /// "Final answer".
  List<TurnEvent> onFinalAnswerTap(int tMs) {
    if (answerEnded) return const [];
    final events = <TurnEvent>[];
    if (!questionEnded) {
      events.addAll(_endQuestion(QuestionEndReason.button, tMs));
    }
    final end = _answerEnd(tMs);
    tA1 = end;
    return events..add(AnswerEnded(end));
  }

  /// Where the scored answer ends for a Final answer tap at [tapMs]: the
  /// tap, or [TurnConfig.answerTailMs] after the player last spoke if that's
  /// sooner, and never more than [TurnConfig.maxAnswerMs] after the question
  /// ended (or before it, or before the answer started).
  int _answerEnd(int tapMs) {
    final end = tQ1!;
    final cap = math.min(tapMs, end + config.maxAnswerMs);
    final start = tA0;
    if (start == null || _talk.talking || _talk.rawTalking) {
      return math.max(cap, start ?? end);
    }
    final last = math.max(lastPlayerActivityMs ?? start, start);
    return math.max(math.min(cap, last + config.answerTailMs), start);
  }

  /// Clock tick: confirms debounced talk edges. Nothing ends on a tick.
  List<TurnEvent> tick(int nowMs) => _confirm(_talk.settle(nowMs));

  List<TurnEvent> _confirm(List<(bool, int)> transitions) {
    final events = <TurnEvent>[];
    for (final (talking, t) in transitions) {
      if (talking) {
        events.addAll(_onTalkStart(t));
      } else {
        lastPlayerActivityMs = math.max(lastPlayerActivityMs ?? 0, t);
      }
    }
    return events;
  }

  List<TurnEvent> _onTalkStart(int t) {
    if (answerEnded) return const [];
    if (!questionEnded) {
      // Noted, not acted on: only a tap ends the question.
      if (party && lastAskerSpeechMs != null) earlyTalkMs ??= t;
      return const [];
    }
    lastPlayerActivityMs = math.max(lastPlayerActivityMs ?? 0, t);
    if (tA0 == null) {
      tA0 = t;
      return [AnswerStarted(t)];
    }
    return const [];
  }

  /// Ends the question for a tap (or the host finishing) at [tapMs]. In
  /// party mode the question really ended with the asker's last words, so
  /// that's tQ1, and hesitation counts from there, less a moment for the
  /// tap: a slow tap can't hide a slow answer.
  List<TurnEvent> _endQuestion(QuestionEndReason reason, int tapMs) {
    tQ0 ??= startMs;
    final asked = lastAskerSpeechMs;
    final end = party && asked != null && asked < tapMs ? asked : tapMs;
    tQ1 = end;
    questionEndReason = reason;
    final early = earlyTalkMs;
    // Answering before the tap: no tap came first, so no allowance.
    hesitationFromMs = early != null ? end : _pauseFrom(end, tapMs);
    final events = <TurnEvent>[QuestionEnded(reason, end)];
    if (early != null || _talk.talking) {
      // Already answering: from when they started, or the question's end if
      // they were talking over it.
      final start = math.max(early ?? _talk.lastStartMs ?? end, end);
      tA0 = start;
      lastPlayerActivityMs = math.max(lastPlayerActivityMs ?? start, start);
      events.add(AnswerStarted(start));
    }
    return events;
  }

  /// Timing markers once the answer has ended.
  QuestionTiming timing() => QuestionTiming(
    tQ0: tQ0 ?? startMs,
    tQ1: tQ1 ?? startMs,
    tA0: tA0,
    tA1: tA1 ?? tQ1 ?? startMs,
    hesitationFromMs: hesitationFromMs ?? tQ1 ?? startMs,
  );
}
