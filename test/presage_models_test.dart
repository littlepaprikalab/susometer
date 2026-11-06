import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/presage/presage_models.dart';

void main() {
  group('PresageSample.fromMap', () {
    test('parses a full snapshot from the bridge', () {
      final s = PresageSample.fromMap({
        't': 1730851200123,
        'status': 'running',
        'pulse': 84.0,
        'pulseConf': 0.82,
        'pulseAt': 1730851200100,
        'pulseStable': true,
        'rmssd': 41.2,
        'hrvConf': 0.55,
        'hrvStable': false,
        'blink': false,
        'talking': true,
        'expr': {'surprise': 0.42, 'neutral': 0.5, 'fear': 0.08},
        'exprAt': 1730851200090,
        'validation': {'code': 'OK', 'hint': 'Hold still'},
        'events': [
          {'e': 'blinkEvent', 't': 1730851200050, 'ts': 1730851200050000},
          {'e': 'talkStart', 't': 1730851200060},
          {'e': 'bogus', 't': 1},
        ],
        'trace': [0.1, 0.2, 0.3],
        'insightSeen': false,
      });

      expect(s.tMs, 1730851200123);
      expect(s.status, PresageStatus.running);
      expect(s.pulse, 84.0);
      expect(s.pulseConf, 0.82);
      expect(s.pulseAtMs, 1730851200100);
      expect(s.pulseStable, isTrue);
      expect(s.rmssd, 41.2);
      expect(s.talking, isTrue);
      expect(s.validation!.isOk, isTrue);
      expect(s.validation!.hint, 'Hold still');
      expect(s.events, hasLength(2), reason: 'unknown edges are dropped');
      expect(s.events.first.type, PresageEdgeType.blink);
      expect(s.events.first.sdkTsUs, 1730851200050000);
      expect(s.events.last.type, PresageEdgeType.talkStart);
      expect(s.trace, [0.1, 0.2, 0.3]);
      expect(s.topExpression!.key, 'neutral');
      expect(s.exprAtMs, 1730851200090);
      expect(s.error, isNull);
    });

    test('tolerates missing optional fields and ints for doubles', () {
      final s = PresageSample.fromMap({'t': 5, 'status': 'idle', 'pulse': 72});
      expect(s.status, PresageStatus.idle);
      expect(s.pulse, 72.0);
      expect(s.pulseConf, isNull);
      expect(s.rmssd, isNull);
      expect(s.validation, isNull);
      expect(s.expr, isEmpty);
      expect(s.exprAtMs, isNull);
      expect(s.events, isEmpty);
      expect(s.topExpression, isNull);
      expect(s.insightSeen, isFalse);
    });

    test('parses an SDK error and an unknown status', () {
      final s = PresageSample.fromMap({
        't': 1,
        'status': 'weird',
        'error': {
          'code': 'authenticationFailed',
          'codeNum': 2,
          'message': 'Invalid API key',
          'retryable': false,
        },
        'validation': {'code': 'NO_FACE_FOUND', 'hint': 'No face'},
      });
      expect(s.status, PresageStatus.unknown);
      expect(s.error!.code, 'authenticationFailed');
      expect(s.error!.codeNum, 2);
      expect(s.validation!.faceMissing, isTrue);
      expect(s.validation!.isOk, isFalse);
    });
  });

  test('ConnectionTestResult.fromMap', () {
    final ok = ConnectionTestResult.fromMap({
      'ok': true,
      'code': 'OK',
      'message': 'Connected',
      'phase': 'running',
      'ms': 2450,
      'startMs': 300,
    });
    expect(ok.ok, isTrue);
    expect(ok.elapsedMs, 2450);
    expect(ok.startMs, 300);
    expect(ok.phase, 'running');

    final bad = ConnectionTestResult.fromMap({
      'ok': false,
      'code': 'authenticationFailed',
      'message': 'nope',
      'phase': 'start',
    });
    expect(bad.ok, isFalse);
    expect(bad.code, 'authenticationFailed');
  });
}
