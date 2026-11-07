import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/voice/speech_service.dart';

import 'world.dart';

const measuring = {
  GamePhase.calibrate,
  GamePhase.ask,
  GamePhase.answer,
  GamePhase.settle,
};

const needsTurns = {
  GamePhase.howToPlay,
  GamePhase.consent,
  GamePhase.calibrate,
  GamePhase.ask,
  GamePhase.answer,
  GamePhase.settle,
  GamePhase.redo,
  GamePhase.callIt,
  GamePhase.countdown,
  GamePhase.verdict,
  GamePhase.sdkOffline,
  GamePhase.leaderboard,
  GamePhase.replay,
};

final Map<GamePhase, int> phaseCounts = {};

/// Every scored result the invariants saw, to count how their pulse part
/// was worked out.
final Set<QuestionResult> seenResults = Set.identity();

/// Random user actions and environment failures against one game.
void abuse(
  World w,
  Random rng,
  int steps,
  List<Object> errors, {
  bool biased = false,
}) {
  final g = w.game;
  void ensurePlayers() {
    while (g.players.length < 3) {
      g.addPlayer('P${g.players.length}');
    }
  }

  // Biased mode: forward-moving actions and good conditions dominate, so
  // runs reach questions, votes, verdicts and the leaderboard.
  int fw(int chaos, int forward) => biased ? forward : chaos;
  final actions = <(int, void Function())>[
    (
      fw(3, 6),
      () {
        if (g.phase == GamePhase.lobby) {
          ensurePlayers();
          w.presage.storedKey = 'k';
          g.startShow();
        }
      },
    ),
    (
      fw(1, 1),
      () => g.setMode(rng.nextBool() ? GameMode.party : GameMode.solo),
    ),
    // Lobby settings poked at any moment must be no-ops mid-game.
    (
      fw(2, 1),
      () {
        switch (rng.nextInt(4)) {
          case 0:
            g.setQuestionsPerTurn(const [3, 5, 7][rng.nextInt(3)]);
          case 1:
            g.setDeck(rng.nextBool() ? DeckKind.mild : DeckKind.spicy);
          case 2:
            if (g.players.isNotEmpty) {
              g.removePlayer(g.players[rng.nextInt(g.players.length)].id);
            }
          default:
            g.addPlayer('Late${rng.nextInt(99)}');
        }
      },
    ),
    (fw(2, 6), g.dismissHowToPlay),
    (fw(2, 2), g.playWithoutVoice),
    (fw(4, 10), () => g.agreeToMeasure()),
    (fw(2, 1), () => g.skipTurn()),
    (fw(2, 1), g.skipWarmup),
    (fw(3, 8), g.nextWarmup),
    (fw(3, 8), g.startQuestions),
    (fw(4, 12), g.doneAsking),
    // Nothing ends by itself (decision 76), so the biased player taps
    // Final answer and Reveal more often than the timers used to fire.
    (fw(4, 18), g.finalAnswer),
    (fw(2, 1), g.differentQuestion),
    (fw(2, 4), g.readyToAnswer),
    (
      fw(3, 4),
      () {
        if (g.inGame && g.phase == GamePhase.callIt) {
          final v = g.voters;
          if (v.isNotEmpty) {
            g.castVote(
              v[rng.nextInt(v.length)].id,
              rng.nextBool() ? Vote.legit : Vote.sus,
            );
          }
        }
      },
    ),
    (fw(3, 20), g.reveal),
    (fw(4, 14), () => g.nextQuestion()),
    (fw(2, 2), () => g.endTurn()),
    (fw(2, 1), () => g.skipQuestion()),
    (fw(2, 6), g.askAgain),
    (fw(2, 1), g.pause),
    (fw(3, 8), () => g.resume()),
    (fw(1, 0), () => g.endShowEarly()),
    (fw(1, 1), () => g.playAgain()),
    (fw(1, 0), () => g.wipeAll()),
    (fw(2, 6), () => g.retrySdk()),
    (fw(1, 0), () => g.backToLobby()),
    (fw(1, 2), g.openReplay),
    (fw(1, 2), g.backToLeaderboard),
    (fw(1, 1), () => g.onAppBackgrounded()),
    (fw(1, 1), () => g.onAppResumed()),
    (fw(1, 1), g.onAppInactive),
    // A trip out of the app in the order Flutter reports it on iOS: a
    // screenshot (back within the auto-resume window) or a longer one.
    (
      fw(2, 2),
      () {
        final ms = rng.nextBool()
            ? rng.nextInt(GameController.autoResumeWithinMs)
            : GameController.autoResumeWithinMs + rng.nextInt(20000);
        final said = w.host.said.length;
        w.leaveApp(
          ms,
          whileAway: () {
            if (!g.paused || !g.cameraStopped) return;
            expect(w.running, isFalse, reason: 'camera running while away');
            expect(w.host.said.length, said, reason: 'host spoke while away');
          },
        );
        // Time away isn't a stall: the turn was paused, and the clock for
        // getting the ticker back starts on return.
        _stalledSince[w] = null;
      },
    ),
    // Native starts that take a while, so trips land while they run.
    (
      fw(1, 1),
      () {
        w.startTakesMs = rng.nextInt(3) == 0 ? rng.nextInt(1500) : 0;
        w.speech.startTakesMs = rng.nextInt(3) == 0 ? rng.nextInt(800) : 0;
      },
    ),
    (fw(1, 1), () => g.recheckPermissions()),
    // Environment.
    (fw(2, 1), () => w.emitting = rng.nextInt(biased ? 12 : 4) != 0),
    (fw(2, 1), () => w.cameraFrozen = rng.nextInt(biased ? 12 : 4) == 0),
    (
      fw(2, 1),
      () {
        w.code = biased
            ? (rng.nextInt(8) == 0 ? 'TOO_DARK' : 'OK')
            : const [
                'OK',
                'OK',
                'TOO_DARK',
                'EXCESSIVE_MOTION',
                'NO_FACE_FOUND',
              ][rng.nextInt(5)];
      },
    ),
    (
      fw(1, 0),
      () => w.status = const [
        'running',
        'running',
        'running',
        'error',
        'starting',
      ][rng.nextInt(5)],
    ),
    (
      fw(1, 1),
      () {
        w.presage.startError = rng.nextInt(biased ? 10 : 3) == 0
            ? const PresageException('networkError', 'offline')
            : null;
      },
    ),
    // The pulse waveform (SPEC.md decision 63): on and off, a heart rate
    // that steps between 65 and 90, a misbehaving SDK clock, and the Proof
    // Panel's live beat readout.
    (
      fw(1, 1),
      () => w.heart = rng.nextInt(4) == 0
          ? null
          : (t) => 65.0 + 25 * ((t ~/ 7000) % 2),
    ),
    (
      fw(1, 0),
      () => w.waveChaos = rng.nextBool() ? Random(rng.nextInt(1 << 30)) : null,
    ),
    (fw(1, 1), () => w.settings.proofPanel = rng.nextBool()),
    (fw(3, 4), () => w.talk(rng.nextBool())),
    (fw(3, 4), () => w.say('words ${rng.nextInt(1000)}')),
    (
      fw(1, 0),
      () => w.speech.controller.add(
        const SpeechError('RECOGNIZER_FAILING', 'x', 0),
      ),
    ),
    (
      fw(1, 0),
      () => w.device.camera = rng.nextInt(4) == 0 ? 'denied' : 'granted',
    ),
    (
      fw(1, 1),
      () => w.device.thermal = rng.nextInt(5) == 0 ? 'serious' : 'nominal',
    ),
    (fw(8, 30), () => w.elapse(rng.nextInt(biased ? 15000 : 6000))),
  ];
  final total = actions.fold<int>(0, (a, e) => a + e.$1);

  for (var step = 0; step < steps; step++) {
    var pick = rng.nextInt(total);
    for (final (weight, action) in actions) {
      if (pick < weight) {
        action();
        break;
      }
      pick -= weight;
    }
    w.elapse(100);
    phaseCounts[g.phase] = (phaseCounts[g.phase] ?? 0) + 1;
    checkInvariants(w, errors, 'step $step');
  }
}

/// When each world's turn was first seen without its ticker.
final _stalledSince = Expando<int>();

void checkInvariants(World w, List<Object> errors, String where) {
  final g = w.game;
  if (errors.isNotEmpty) fail('$where: uncaught error ${errors.first}');
  // Liveness: a question or calibration that isn't paused gets its ticker
  // back within moments (a slow camera start is the longest wait). Without
  // it nothing moves the turn on, not even the watchdog.
  if (measuring.contains(g.phase) && !g.paused && !g.tickerRunning) {
    final since = _stalledSince[w] ??= w.now;
    expect(
      w.now - since,
      lessThan(5000),
      reason: '$where: ${g.phase} stalled without its ticker',
    );
  } else {
    _stalledSince[w] = null;
  }
  if (needsTurns.contains(g.phase)) {
    expect(g.turns, isNotEmpty, reason: '$where: ${g.phase} without a game');
    expect(
      g.playerIndex,
      inInclusiveRange(0, g.turns.length - 1),
      reason: where,
    );
  }
  expect(
    g.log.trace.length,
    lessThanOrEqualTo(g.log.maxTracePoints),
    reason: where,
  );
  for (final v in [
    g.live.waveHz,
    g.live.beatBpm,
    g.live.beatRmssdMs,
    g.live.beatCoverage,
  ]) {
    if (v != null) expect(v.isFinite, isTrue, reason: '$where: live beats');
  }
  for (final t in g.turns) {
    for (final r in t.results) {
      final b = r.breakdown;
      if (b == null) continue;
      seenResults.add(r);
      expect(b.zPulse, inInclusiveRange(0, 1), reason: '$where: zPulse');
      if (b.pulseMethod == PulseMethod.beats) {
        expect(b.shape, isNotNull, reason: where);
        expect(b.pulseNote, isNull, reason: where);
        expect(r.features?.pulseShape, isNotNull, reason: where);
      } else {
        expect(b.pulseNote, isNotNull, reason: '$where: no fallback reason');
      }
    }
    expect(
      t.results.length,
      lessThanOrEqualTo(g.questionsPerTurn),
      reason: '$where: too many results',
    );
    final indices = t.results.map((r) => r.index).toList();
    expect(
      indices.toSet().length,
      indices.length,
      reason: '$where: duplicate question index $indices',
    );
  }
  if (g.phase == GamePhase.lobby) expect(g.paused, isFalse, reason: where);
  // Privacy: the camera never runs outside a turn.
  const cameraOff = {
    GamePhase.lobby,
    GamePhase.howToPlay,
    GamePhase.permissions,
    GamePhase.consent,
    GamePhase.sdkOffline,
    GamePhase.leaderboard,
    GamePhase.replay,
  };
  if (cameraOff.contains(g.phase)) {
    expect(w.running, isFalse, reason: '$where: camera running in ${g.phase}');
    expect(
      g.live.expression.tag,
      isNull,
      reason: '$where: an expression tag outlived the camera (${g.phase})',
    );
    expect(
      g.visibleIssue,
      isNull,
      reason: '$where: a camera problem outlived the camera (${g.phase})',
    );
  }
  if (g.phase != GamePhase.calibrate) {
    expect(
      g.calibIssue,
      isNull,
      reason: '$where: a calibration hint outside calibration (${g.phase})',
    );
  }
  expect(
    w.haptics.cues.where((c) => measuring.contains(c.$2)),
    isEmpty,
    reason: '$where: haptic while measuring',
  );
}

/// Gets back to the lobby using only buttons a user has.
void rescue(World w, int seed) {
  final g = w.game;
  w
    ..emitting = true
    ..cameraFrozen = false
    ..code = 'OK'
    ..status = 'running';
  w.presage.startError = null;
  w.startTakesMs = 0;
  w.speech.startTakesMs = 0;
  w.device.camera = 'granted';
  // Liveness: with conditions restored, E5 "Try again" must lead back in.
  if (g.phase == GamePhase.sdkOffline && !g.paused) {
    w.elapse(700);
    g.retrySdk();
    w.elapse(500);
    expect(
      g.phase,
      isNot(GamePhase.sdkOffline),
      reason: 'seed $seed: Try again stayed on E5',
    );
    expect(
      w.running,
      isTrue,
      reason: 'seed $seed: Try again did not restart the camera',
    );
  }
  for (var i = 0; i < 15 && g.phase != GamePhase.lobby; i++) {
    if (g.paused) {
      g.resume();
    } else {
      switch (g.phase) {
        case GamePhase.permissions ||
            GamePhase.sdkOffline ||
            GamePhase.howToPlay:
          g.backToLobby();
        case GamePhase.leaderboard || GamePhase.replay:
          g.playAgain();
        case GamePhase.consent:
          if (g.playerIndex == 0 && g.turns.every((t) => t.results.isEmpty)) {
            g.backToLobby();
          } else {
            g.endShowEarly();
          }
        default:
          g.endShowEarly();
      }
    }
    w.elapse(800);
  }
  expect(
    g.phase,
    GamePhase.lobby,
    reason: 'seed $seed: could not get back to the lobby',
  );
}

/// After the abuse, a clean game must still play to the end.
void playCleanGame(World w, int seed) {
  final g = w.game;
  g.setMode(GameMode.party);
  while (g.players.length < 2) {
    g.addPlayer('P${g.players.length}');
  }
  while (g.players.length > 2) {
    g.removePlayer(g.players.last.id);
  }
  g.setQuestionsPerTurn(3);
  w.presage.storedKey = 'k';
  w.speech.permissions = const SpeechPermissions(
    mic: 'granted',
    speech: 'authorized',
    onDevice: true,
  );
  w.elapse(700);
  g.startShow();
  w.elapse(200);
  if (g.phase == GamePhase.howToPlay) g.dismissHowToPlay();
  expect(g.phase, GamePhase.consent, reason: 'seed $seed');
  for (var p = 0; p < 2; p++) {
    w.elapse(700);
    w.calibrate();
    for (var q = 0; q < 3; q++) {
      w.askAndAnswer();
      w.elapse(700);
      g.nextQuestion();
      w.elapse(200);
    }
  }
  expect(
    g.phase,
    GamePhase.leaderboard,
    reason: 'seed $seed: clean game did not finish',
  );
  expect(g.awards!.ranked.length, 2);
}

void main() {
  test(
    'progress-biased random play reaches every screen and never breaks (60 seeds)',
    () {
      phaseCounts.clear();
      seenResults.clear();
      for (var seed = 1000; seed < 1060; seed++) {
        final errors = <Object>[];
        runZonedGuarded(() {
          fakeAsync((async) {
            final rng = Random(seed);
            final w = World(async);
            abuse(w, rng, 400, errors, biased: true);
            rescue(w, seed);
            checkInvariants(w, errors, 'seed $seed end');
            w.dispose();
            async.flushTimers(flushPeriodicTimers: false);
          });
        }, (e, st) => errors.add('$e\n$st'));
        if (errors.isNotEmpty) fail('seed $seed: ${errors.first}');
      }
      // ignore: avoid_print
      print('FUZZ (biased) phases visited: $phaseCounts');
      final methodCounts = <PulseMethod, int>{};
      for (final r in seenResults) {
        final m = r.breakdown!.pulseMethod;
        methodCounts[m] = (methodCounts[m] ?? 0) + 1;
      }
      // ignore: avoid_print
      print('FUZZ (biased) pulse scored by: $methodCounts');
      for (final m in PulseMethod.values) {
        expect(
          methodCounts[m] ?? 0,
          greaterThan(0),
          reason: 'fuzzer never scored a pulse by ${m.name}',
        );
      }
      for (final p in [
        GamePhase.calibrate,
        GamePhase.ask,
        GamePhase.answer,
        GamePhase.settle,
        GamePhase.callIt,
        GamePhase.countdown,
        GamePhase.verdict,
        GamePhase.leaderboard,
        GamePhase.redo,
        GamePhase.sdkOffline,
      ]) {
        expect(
          phaseCounts[p] ?? 0,
          greaterThan(0),
          reason: 'fuzzer never reached $p',
        );
      }
    },
  );

  test('random play and failures never break the game (100 seeds)', () {
    phaseCounts.clear();
    for (var seed = 0; seed < 100; seed++) {
      final errors = <Object>[];
      runZonedGuarded(() {
        fakeAsync((async) {
          final rng = Random(seed);
          final w = World(async);
          abuse(w, rng, 150, errors);
          rescue(w, seed);
          if (seed % 10 == 0) playCleanGame(w, seed);
          checkInvariants(w, errors, 'seed $seed end');
          w.dispose();
          async.flushTimers(flushPeriodicTimers: false);
        });
      }, (e, st) => errors.add('$e\n$st'));
      if (errors.isNotEmpty) fail('seed $seed: ${errors.first}');
    }
    // ignore: avoid_print
    print('FUZZ phases visited: $phaseCounts');
  });
}
