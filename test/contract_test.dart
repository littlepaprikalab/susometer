// Contract tests for the Dart <-> Swift seams. The platform channels are
// stringly typed, so these read the Swift sources and check that every name
// Dart depends on is really there. They run without a Mac or a device.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/audio/host_audio.dart';
import 'package:susometer/game/expression_tag.dart';
import 'package:susometer/game/scoring.dart';
import 'package:susometer/game/scoring_config.dart';
import 'package:susometer/settings/app_settings.dart';

String read(String path) => File(path).readAsStringSync();

final presageSwift = read('ios/Runner/Presage/PresageBridge.swift');
final previewSwift = read('ios/Runner/Presage/CameraPreviewView.swift');
final speechSwift = read('ios/Runner/Voice/SpeechBridge.swift');
final deviceSwift = read('ios/Runner/Device/DeviceBridge.swift');
final appDelegate = read('ios/Runner/AppDelegate.swift');

/// Method names a Swift handler switches on: `case "name":`.
Set<String> swiftCases(String source) => {
  for (final m in RegExp(r'case "([A-Za-z]+)":').allMatches(source))
    m.group(1)!,
};

/// Method names a Dart wrapper invokes: `_call<...>('name'` or `invokeMethod<...>('name'`.
Set<String> dartCalls(String source) => {
  for (final m in RegExp(
    r"(?:_call|invokeMethod)(?:<[^(]*>)?\(\s*'([A-Za-z]+)'",
  ).allMatches(source))
    m.group(1)!,
};

void expectAllIn(Iterable<String> names, String source, String where) {
  for (final n in names) {
    expect(source.contains('"$n"'), isTrue, reason: '"$n" missing from $where');
  }
}

void main() {
  group('channel names match on both sides', () {
    test('presage', () {
      expect(presageSwift, contains('"sus/presage"'));
      expect(presageSwift, contains('"sus/presage/stream"'));
      expect(
        read('lib/presage/presage_channel.dart'),
        contains("'sus/presage'"),
      );
      expect(
        read('lib/presage/presage_channel.dart'),
        contains("'sus/presage/stream'"),
      );
    });
    test('speech', () {
      expect(speechSwift, contains('"sus/speech"'));
      expect(speechSwift, contains('"sus/speech/stream"'));
      expect(read('lib/voice/speech_service.dart'), contains("'sus/speech'"));
      expect(
        read('lib/voice/speech_service.dart'),
        contains("'sus/speech/stream'"),
      );
      expect(read('lib/audio/host_audio.dart'), contains("'sus/speech'"));
    });
    test('device', () {
      expect(deviceSwift, contains('"sus/device"'));
      expect(read('lib/device/device_api.dart'), contains("'sus/device'"));
    });
    test('camera preview platform view', () {
      expect(previewSwift, contains('"sus/camera_preview"'));
      expect(
        read('lib/presage/camera_preview.dart'),
        contains("'sus/camera_preview'"),
      );
      expect(previewSwift, contains('params["mirror"]'));
      // The preview resizes with its box, so it must follow its container
      // and must not mirror with a view transform (frame undefined).
      expect(previewSwift, contains('.flexibleWidth, .flexibleHeight'));
      expect(previewSwift, contains('withHorizontallyFlippedOrientation'));
      expect(previewSwift, isNot(contains('.transform =')));
    });
    test('all bridges are registered at launch', () {
      for (final b in ['PresageBridge', 'SpeechBridge', 'DeviceBridge']) {
        expect(appDelegate, contains('$b.register(with: registrar)'));
      }
    });
  });

  group('every method Dart calls is handled in Swift', () {
    test('presage', () {
      final calls = dartCalls(read('lib/presage/presage_channel.dart'));
      expect(
        calls,
        containsAll([
          'configure',
          'setApiKey',
          'hasApiKey',
          'apiKeyHint',
          'clearApiKey',
          'testConnection',
          'start',
          'stop',
          'reset',
          'sdkInfo',
        ]),
      );
      expect(swiftCases(presageSwift), containsAll(calls));
    });
    test('speech and host audio', () {
      final calls = {
        ...dartCalls(read('lib/voice/speech_service.dart')),
        ...dartCalls(read('lib/audio/host_audio.dart')),
      };
      expect(
        calls,
        containsAll([
          'permissionStatus',
          'requestPermissions',
          'start',
          'stop',
          'pause',
          'resume',
          'newSegment',
          'speak',
          'stopSpeaking',
          'playSound',
        ]),
      );
      expect(swiftCases(speechSwift), containsAll(calls));
    });
    test('device', () {
      final calls = dartCalls(read('lib/device/device_api.dart'));
      expect(
        calls,
        containsAll([
          'cameraPermission',
          'requestCameraPermission',
          'openAppSettings',
          'openPortal',
          'setKeepAwake',
          'thermalState',
          'shareImage',
        ]),
      );
      expect(swiftCases(deviceSwift), containsAll(calls));
    });
  });

  group('argument and payload keys', () {
    test('presage snapshot keys Dart parses are emitted by Swift', () {
      expectAllIn(
        [
          't',
          'status',
          'pulse',
          'pulseConf',
          'pulseAt',
          'pulseStable',
          'rmssd',
          'hrvConf',
          'hrvStable',
          'blink',
          'talking',
          'expr',
          'exprAt',
          'frameAt',
          'validation',
          'error',
          'events',
          'trace',
          'traceTs',
          'traceConf',
          'insightSeen',
          'insight',
        ],
        presageSwift,
        'PresageBridge snapshot',
      );
      expectAllIn(
        ['count', 'kind', 'chars', 'at', 'analysis', 'empty'],
        presageSwift,
        'PresageBridge insight summary',
      );
      expectAllIn(
        ['code', 'hint', 'codeNum', 'message', 'retryable', 'e', 'ts'],
        presageSwift,
        'PresageBridge maps',
      );
      expectAllIn(
        ['blinkEvent', 'talkStart', 'talkEnd'],
        presageSwift,
        'PresageBridge edges',
      );
      expectAllIn(
        ['idle', 'starting', 'running', 'stopping', 'error'],
        presageSwift,
        'statusName',
      );
    });
    test('method arguments', () {
      expect(presageSwift, contains('args["telemetry"]'));
      expect(presageSwift, contains('args["key"]'));
      expect(speechSwift, contains('args["locale"]'));
      expect(speechSwift, contains('args["text"]'));
      expect(speechSwift, contains('args["name"]'));
      expect(deviceSwift, contains('args["on"]'));
      expect(deviceSwift, contains('args["png"]'));
      expect(deviceSwift, contains('args["text"]'));
    });
    test('test connection result keys', () {
      expectAllIn(
        ['ok', 'code', 'message', 'phase', 'ms', 'startMs'],
        presageSwift,
        'testConnection',
      );
      expectAllIn(
        ['NO_KEY', 'BUSY', 'TIMEOUT'],
        presageSwift,
        'testConnection codes',
      );
    });
    test('speech events and permission values', () {
      expectAllIn(
        [
          'type',
          'partial',
          'final',
          'level',
          'state',
          'text',
          'seg',
          'code',
          'message',
        ],
        speechSwift,
        'speech events',
      );
      expectAllIn(
        ['listening', 'paused', 'stopped'],
        speechSwift,
        'speech states',
      );
      expectAllIn(
        ['mic', 'speech', 'onDevice'],
        speechSwift,
        'permissionStatus',
      );
      expectAllIn(
        ['granted', 'denied', 'undetermined', 'authorized', 'notDetermined'],
        speechSwift,
        'permission values',
      );
      expectAllIn(
        ['RECOGNIZER_FAILING', 'ON_DEVICE_UNAVAILABLE', 'MIC_DENIED'],
        speechSwift,
        'speech error codes',
      );
    });
    test('camera permission and thermal values', () {
      expectAllIn(
        ['granted', 'denied', 'undetermined', 'restricted'],
        deviceSwift,
        'cameraPermission',
      );
      expectAllIn(
        ['nominal', 'fair', 'serious', 'critical'],
        deviceSwift,
        'thermalState',
      );
    });
  });

  test('the test fakes send the same snapshot keys as the Swift bridge', () {
    for (final fake in ['test/rig.dart', 'test/world.dart']) {
      final src = read(fake);
      for (final key in [
        't',
        'status',
        'pulse',
        'pulseConf',
        'pulseAt',
        'expr',
        'exprAt',
        'frameAt',
      ]) {
        expect(src, contains("'$key':"), reason: '$fake: $key');
      }
      for (final key in ['talking', 'validation', 'events']) {
        expect(presageSwift, contains('"$key"'));
        expect(src, contains("'$key':"), reason: '$fake: $key');
      }
    }
  });

  test('expression names agree: bridge, tag, score and stamp', () {
    // `case .fear: return "fear"` inside PresageBridge.expressionName.
    final fn = RegExp(
      r'func expressionName\(.*?\n  \}',
      dotAll: true,
    ).firstMatch(presageSwift)!.group(0)!;
    final swiftNames = {
      for (final m in RegExp(r'case \.(\w+): return "(\w+)"').allMatches(fn))
        if (m.group(1) == m.group(2)) m.group(2)!,
    }..remove('unspecified');
    expect(swiftNames, ExpressionTagger.labels.toSet());
    expect(
      ExpressionTagger.labels,
      containsAll(const ScoringConfig().exprCategories),
      reason: 'every scored category can show as a red tag',
    );
    // The bridge's fallbacks never pass as a tag.
    expect(fn, contains('"unspecified"'));
    expect(fn, contains('"unknown'));
    for (final odd in ['unspecified', 'unknown', 'unknown7']) {
      expect(ExpressionTagger.labels, isNot(contains(odd)));
    }
    // Confidence arrives as a percentage and is sent as 0..1, which the
    // tagger's 0.3 threshold assumes.
    expect(presageSwift, contains('Double(score.confidence) / 100.0'));
  });

  group('codes Dart reacts to are codes Swift sends', () {
    test('SDK error names', () {
      for (final code in ApiKeyController.keyErrorCodes) {
        expect(presageSwift, contains('"$code"'));
      }
      for (final code in ['networkError', 'serverError', 'inputUnavailable']) {
        expect(presageSwift, contains('"$code"'));
        expect(
          describePresageCode(code, ''),
          isNot(code),
          reason: 'has friendly text',
        );
      }
    });
    test('every code string Dart matches on is one Swift sends', () {
      // Codes Dart makes up itself: off-iPhone, engine paused, watchdog,
      // slow calibration's hint (SPEC.md decision 69).
      const dartMade = {
        'UNAVAILABLE',
        'NOT_RUNNING',
        'NO_SIGNAL',
        'STILL_CALIBRATING',
      };
      final swift = [presageSwift, speechSwift, deviceSwift].join('\n');
      final pattern = RegExp(r"'([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+|BUSY|OK)'");
      final codes = <String, String>{};
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final m in pattern.allMatches(f.readAsStringSync())) {
          codes[m[1]!] = f.path;
        }
      }
      expect(codes.length, greaterThan(15), reason: 'the scan found codes');
      for (final MapEntry(key: code, value: file) in codes.entries) {
        if (dartMade.contains(code)) continue;
        expect(
          swift,
          contains('"$code"'),
          reason: '$file matches on $code, which no Swift bridge sends',
        );
      }
    });
    test('validation codes used by the game', () {
      expectAllIn(
        [
          'OK',
          'NO_FACE_FOUND',
          'MULTIPLE_FACES_FOUND',
          'CAMERA_TUNING',
          'TOO_DARK',
          'TOO_BRIGHT',
          'EXCESSIVE_MOTION',
          'FACE_TOO_FAR',
          'FACE_TOO_CLOSE',
          'FACE_NOT_CENTERED',
          'FACE_NOT_FORWARD',
          'FRAME_RATE_TOO_LOW',
        ],
        presageSwift,
        'validationName',
      );
    });
    test('every validation code the bridge sends gets its own stamp', () {
      // The body of Swift's validationName, so a code added there without
      // a stamp in Dart fails here instead of showing "Adjusting".
      final start = presageSwift.indexOf('func validationName(');
      expect(start, greaterThan(0), reason: 'validationName not found');
      final body = presageSwift.substring(
        start,
        presageSwift.indexOf('\n  }\n', start),
      );
      final named = [
        for (final m in RegExp(r'"([A-Z][A-Z_]+)"').allMatches(body)) m[1]!,
      ];
      expect(named.length, greaterThan(14), reason: 'the scan found codes');
      const nothingToFix = {'OK', 'CAMERA_TUNING', 'CHEST_NOT_VISIBLE'};
      for (final code in named) {
        final issue = SignalIssue.fromCode(code);
        if (nothingToFix.contains(code)) {
          expect(issue, isNull, reason: '$code stamps nothing');
          continue;
        }
        expect(issue, isNotNull, reason: code);
        expect(issue!.stamp, isNot('Adjusting'), reason: '$code has no stamp');
        expect(issue.stamp.length, lessThanOrEqualTo(14), reason: code);
        expect(issue.fix, isNotEmpty, reason: code);
      }
      // A code from a newer SDK ("CODE_<n>") still gets a stamp.
      expect(body, contains('"CODE_'));
      expect(SignalIssue.fromCode('CODE_42')?.stamp, 'Adjusting');
    });
  });

  group('assets', () {
    test('every sound effect file exists and is bundled', () {
      final pubspec = read('pubspec.yaml');
      expect(pubspec, contains('- assets/sfx/'));
      for (final s in Sfx.values) {
        expect(
          File('assets/sfx/${s.fileName}.wav').existsSync(),
          isTrue,
          reason: s.fileName,
        );
      }
      expect(speechSwift, contains('assets/sfx/'));
    });
    test('the host voice never lands on a novelty or legacy voice', () {
      for (final s in [
        '.isNoveltyVoice',
        '.isPersonalVoice',
        '"com.apple.speech.synthesis.voice."',
        '"com.apple.eloquence."',
        'voice.quality.rawValue',
      ]) {
        expect(speechSwift, contains(s));
      }
    });
    test('decks and fonts are bundled', () {
      final pubspec = read('pubspec.yaml');
      expect(pubspec, contains('- assets/decks/'));
      for (final f in [
        'BowlbyOneSC-Regular',
        'WorkSans-Medium',
        'WorkSans-SemiBold',
        'WorkSans-Bold',
      ]) {
        expect(File('assets/fonts/$f.ttf').existsSync(), isTrue);
        expect(pubspec, contains('assets/fonts/$f.ttf'));
      }
    });
  });

  group('Xcode project', () {
    final pbx = read('ios/Runner.xcodeproj/project.pbxproj');
    test(
      'every Swift file under ios/Runner is compiled into the Runner target',
      () {
        final files = Directory('ios/Runner')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.swift'))
            .map((f) => f.uri.pathSegments.last);
        for (final name in files) {
          expect(
            pbx,
            contains('$name in Sources'),
            reason: '$name is not in the Xcode target',
          );
        }
      },
    );
    test('SmartSpectra is pinned to 3.4.0 and linked', () {
      expect(
        pbx,
        contains(
          'repositoryURL = "https://github.com/Presage-Security/SmartSpectra-Swift"',
        ),
      );
      expect(pbx, contains('kind = exactVersion;'));
      expect(pbx, contains('version = 3.4.0;'));
      expect(pbx, contains('SmartSpectra in Frameworks'));
    });
    test('iOS 17, iPhone only', () {
      expect(pbx, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0')));
      expect(pbx, contains('IPHONEOS_DEPLOYMENT_TARGET = 17.0'));
      expect(pbx, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2"')));
    });
    test('Info.plist: usage strings, portrait only, debug-only key hook', () {
      final plist = read('ios/Runner/Info.plist');
      for (final k in [
        'NSCameraUsageDescription',
        'NSMicrophoneUsageDescription',
        'NSSpeechRecognitionUsageDescription',
      ]) {
        expect(plist, contains(k));
      }
      expect(plist, contains('UIInterfaceOrientationPortrait'));
      expect(plist, isNot(contains('UIInterfaceOrientationLandscapeLeft')));
      expect(plist, contains(r'$(PRESAGE_API_KEY)'));
      expect(
        read('ios/Flutter/Debug.xcconfig'),
        contains('#include? "Secrets.xcconfig"'),
      );
      expect(read('ios/Flutter/Release.xcconfig'), isNot(contains('Secrets')));
    });
  });

  group('privacy guarantees in the native code (SPEC §8)', () {
    test(
      'breathing metrics are never requested (LLM Insights precondition)',
      () {
        final metrics = RegExp(
          r'requestedMetrics: \[MetricType\] = \[([^\]]*)\]',
        ).firstMatch(presageSwift)!.group(1)!;
        expect(metrics, isNot(contains('breathing')));
        expect(presageSwift, isNot(contains('breathingMetrics')));
        expect(presageSwift, isNot(contains('requestInsight')));
      },
    );
    test('telemetry is switched off before any session', () {
      expect(presageSwift, contains('sdk.config.enableTelemetry = false'));
    });
    test('speech recognition is on-device only, with no server fallback', () {
      expect(
        speechSwift,
        contains('request.requiresOnDeviceRecognition = true'),
      );
      expect(
        speechSwift,
        contains('guard recognizer.supportsOnDeviceRecognition else'),
      );
    });
    test(
      'the Keychain item is device-only and the key never returns to Dart',
      () {
        final keychain = read('ios/Runner/Presage/KeychainStore.swift');
        expect(
          keychain,
          contains('kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly'),
        );
        expect(swiftCases(presageSwift), isNot(contains('getApiKey')));
        expect(
          read('lib/presage/presage_channel.dart'),
          isNot(contains("'getApiKey'")),
        );
      },
    );
    test('no game data is written to disk from Dart', () {
      final libFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final f in libFiles) {
        final src = f.readAsStringSync();
        expect(
          src,
          isNot(contains('dart:io')),
          reason: '${f.path} imports dart:io',
        );
        expect(src, isNot(contains('SharedPreferences')), reason: f.path);
        expect(src, isNot(contains('path_provider')), reason: f.path);
      }
    });
    test('no network or analytics packages', () {
      final pubspec = read('pubspec.yaml');
      for (final p in [
        'http:',
        'dio:',
        'firebase',
        'analytics',
        'sentry',
        'shared_preferences',
      ]) {
        expect(pubspec, isNot(contains(p)), reason: p);
      }
    });
  });
}
