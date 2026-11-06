import 'dart:math' as math;

import '../game/models.dart';

/// Turn-detection constants (SPEC.md §7).
class TurnConfig {
  const TurnConfig({
    this.askerSilenceMs = 1500,
    this.answerSilenceMs = 4000,
    this.noAnswerTimeoutMs = 20000,
    this.talkStartDebounceMs = 200,
    this.talkEndDebounceMs = 500,
    this.speechLevelThreshold = 0.45,
    this.autoQuestionEnd = true,
    this.autoAnswerEnd = true,
  });

  /// Question ends after this much silence following asker speech.
  final int askerSilenceMs;

  /// Answer ends after this much silence following the player's last talk.
  final int answerSilenceMs;

  /// If the player never starts talking, the answer ends after this long.
  final int noAnswerTimeoutMs;

  /// SmartSpectra `talking` must hold this long to count as a talk start.
  final int talkStartDebounceMs;

  /// ...and be off this long to count as a talk end.
  final int talkEndDebounceMs;

  /// Mic level (0..1) that counts as someone still speaking.
  final double speechLevelThreshold;

  /// Detect question end and answer end automatically. Off = tap-to-advance.
  final bool autoQuestionEnd;
  final bool autoAnswerEnd;

  TurnConfig copyWith({bool? autoQuestionEnd, bool? autoAnswerEnd}) =>
      TurnConfig(
        askerSilenceMs: askerSilenceMs,
        answerSilenceMs: answerSilenceMs,
        noAnswerTimeoutMs: noAnswerTimeoutMs,
        talkStartDebounceMs: talkStartDebounceMs,
        talkEndDebounceMs: talkEndDebounceMs,
        speechLevelThreshold: speechLevelThreshold,
        autoQuestionEnd: autoQuestionEnd ?? this.autoQuestionEnd,
        autoAnswerEnd: autoAnswerEnd ?? this.autoAnswerEnd,
      );
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

enum QuestionEndReason { playerTalk, askerSilence, button, hostDone }

enum AnswerEndReason { finalAnswer, silence, noAnswer }

sealed class TurnEvent {
  const TurnEvent(this.tMs);

  final int tMs;
}

class QuestionEnded extends TurnEvent {
  const QuestionEnded(this.reason, int tMs, {required this.hostShouldPrompt})
    : super(tMs);

  final QuestionEndReason reason;

  /// True when the host should say "{name}, your answer?" (silence path).
  final bool hostShouldPrompt;
}

class AnswerStarted extends TurnEvent {
  const AnswerStarted(super.tMs);
}

class AnswerEnded extends TurnEvent {
  const AnswerEnded(this.reason, int tMs) : super(tMs);

  final AnswerEndReason reason;
}

/// Detects question end (tQ1) and answer end (tA1) for one question
/// (SPEC.md §7). Pure: feed it events and clock ticks, read the events back.
///
/// Speaker separation without diarization: mic speech while the player is
/// not talking (per SmartSpectra) is the asker; while talking, the answer.
class TurnDetector {
  TurnDetector({
    required this.party,
    required this.micEnabled,
    required this.startMs,
    this.config = const TurnConfig(),
  }) : _talk = TalkTracker(config) {
    // Solo: the question starts when the host starts reading.
    if (!party) tQ0 = startMs;
  }

  final bool party;
  final bool micEnabled;
  final int startMs;
  final TurnConfig config;
  final TalkTracker _talk;

  int? tQ0;
  int? tQ1;
  int? tA0;
  int? tA1;
  int? hesitationFromMs;
  QuestionEndReason? questionEndReason;
  AnswerEndReason? answerEndReason;
  int? lastAskerSpeechMs;
  int? lastPlayerActivityMs;

  bool get questionEnded => tQ1 != null;
  bool get answerEnded => tA1 != null;
  bool get playerTalking => _talk.talking;

  bool get _autoQuestion => party && micEnabled && config.autoQuestionEnd;
  bool get _autoAnswer => micEnabled && config.autoAnswerEnd;

  /// A raw SmartSpectra talking edge.
  List<TurnEvent> onPlayerTalkEdge(bool talking, int tMs) =>
      _confirm(_talk.edge(talking, tMs));

  /// Recognized speech (new partial text) at [tMs].
  List<TurnEvent> onSpeech(int tMs) {
    if (answerEnded) return const [];
    if (!questionEnded) {
      if (!_talk.talking && !_talk.rawTalking) {
        tQ0 ??= tMs;
        lastAskerSpeechMs = tMs;
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
          !_talk.talking &&
          !_talk.rawTalking) {
        lastAskerSpeechMs = tMs;
      }
    } else if (_talk.talking) {
      lastPlayerActivityMs = math.max(lastPlayerActivityMs ?? 0, tMs);
    }
    return const [];
  }

  /// "Too loud? Tap when done asking" / "Done asking" (no-mic mode).
  List<TurnEvent> onDoneAskingTap(int tMs) {
    if (questionEnded) return const [];
    return _endQuestion(QuestionEndReason.button, tMs, prompt: false);
  }

  /// Solo mode: the host finished reading the question.
  List<TurnEvent> onHostFinishedQuestion(int tMs) {
    if (questionEnded) return const [];
    return _endQuestion(QuestionEndReason.hostDone, tMs, prompt: false);
  }

  /// The host finished "{name}, your answer?". Hesitation counts from here
  /// if the player hasn't started yet, matching how warm-up latency is timed.
  void onHostPromptFinished(int tMs) {
    if (questionEndReason == QuestionEndReason.askerSilence && tA0 == null) {
      hesitationFromMs = tMs;
    }
  }

  List<TurnEvent> onFinalAnswerTap(int tMs) {
    if (answerEnded) return const [];
    final events = <TurnEvent>[];
    if (!questionEnded) {
      events.addAll(_endQuestion(QuestionEndReason.button, tMs, prompt: false));
    }
    tA1 = tMs;
    answerEndReason = AnswerEndReason.finalAnswer;
    return events..add(AnswerEnded(AnswerEndReason.finalAnswer, tMs));
  }

  List<TurnEvent> tick(int nowMs) {
    final events = _confirm(_talk.settle(nowMs));
    if (answerEnded) return events;
    if (!questionEnded) {
      final last = lastAskerSpeechMs;
      if (_autoQuestion &&
          tQ0 != null &&
          last != null &&
          !_talk.talking &&
          !_talk.rawTalking &&
          nowMs - last >= config.askerSilenceMs) {
        events.addAll(
          _endQuestion(QuestionEndReason.askerSilence, nowMs, prompt: true),
        );
      }
      return events;
    }
    if (_autoAnswer) {
      final lastTalk = lastPlayerActivityMs;
      if (tA0 != null &&
          !_talk.talking &&
          lastTalk != null &&
          nowMs - lastTalk >= config.answerSilenceMs) {
        tA1 = nowMs;
        answerEndReason = AnswerEndReason.silence;
        events.add(AnswerEnded(AnswerEndReason.silence, nowMs));
      } else if (tA0 == null &&
          nowMs - (hesitationFromMs ?? tQ1!) >= config.noAnswerTimeoutMs) {
        tA1 = nowMs;
        answerEndReason = AnswerEndReason.noAnswer;
        events.add(AnswerEnded(AnswerEndReason.noAnswer, nowMs));
      }
    }
    return events;
  }

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
      // The player starts answering: that ends the question (rule 1), but
      // only once the asker has said something, or in solo mode.
      final askerSpoke = tQ0 != null && lastAskerSpeechMs != null;
      if ((_autoQuestion && askerSpoke) || (!party && config.autoQuestionEnd)) {
        return _endQuestion(QuestionEndReason.playerTalk, t, prompt: false);
      }
      return const [];
    }
    lastPlayerActivityMs = math.max(lastPlayerActivityMs ?? 0, t);
    if (tA0 == null) {
      tA0 = t;
      return [AnswerStarted(t)];
    }
    return const [];
  }

  List<TurnEvent> _endQuestion(
    QuestionEndReason reason,
    int t, {
    required bool prompt,
  }) {
    tQ0 ??= startMs;
    tQ1 = t;
    questionEndReason = reason;
    hesitationFromMs = t;
    final events = <TurnEvent>[
      QuestionEnded(reason, t, hostShouldPrompt: prompt),
    ];
    final talkingNow = _talk.talking;
    if (reason == QuestionEndReason.playerTalk || talkingNow) {
      tA0 = t;
      lastPlayerActivityMs = t;
      events.add(AnswerStarted(t));
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
