import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/expression_tag.dart';
import 'package:susometer/game/scoring.dart';
import 'package:susometer/theme/expression_stamp.dart';
import 'package:susometer/theme/tokens.dart';

/// Feeds [frames] snapshots 100 ms apart from [from], like the bridge, and
/// returns the time after the last one.
int feed(
  ExpressionTagger t,
  int from,
  int frames,
  Map<String, double> Function(int i) expr, {
  bool faceOk = true,
}) {
  var at = from;
  for (var i = 0; i < frames; i++) {
    t.add(at, expr(i), faceOk: faceOk);
    at += 100;
  }
  return at;
}

const surprised = {'surprise': 0.7, 'neutral': 0.2, 'happy': 0.05};
const calm = {'neutral': 0.8, 'surprise': 0.1, 'happy': 0.05};
const unsure = {'neutral': 0.2, 'happy': 0.2, 'sad': 0.2, 'fear': 0.15};

void main() {
  group('ExpressionTagger', () {
    test('shows the leader once it has held for 0.7 s, not before', () {
      final t = ExpressionTagger();
      var at = feed(t, 0, 7, (_) => surprised);
      expect(t.tag, isNull, reason: '0.6 s in');
      at = feed(t, at, 2, (_) => surprised);
      expect(t.tag, 'surprise');
    });

    test('a brief flicker of another expression does not change the tag', () {
      final t = ExpressionTagger();
      var at = feed(t, 0, 20, (_) => calm);
      expect(t.tag, 'neutral');
      // Three frames of a big surprise: smoothing and the hold absorb it.
      at = feed(t, at, 3, (_) => const {'surprise': 0.95, 'neutral': 0.05});
      at = feed(t, at, 20, (_) => calm);
      expect(t.tag, 'neutral');
    });

    test('two close expressions trading places do not flicker', () {
      final t = ExpressionTagger();
      final changes = <String?>[];
      var at = 0;
      for (var i = 0; i < 100; i++) {
        // The raw top expression flips every frame; happy leads on average,
        // clearly (0.47 vs 0.41).
        final expr = i.isEven
            ? const {'happy': 0.50, 'neutral': 0.36}
            : const {'happy': 0.44, 'neutral': 0.46};
        if (t.add(at, expr, faceOk: true)) changes.add(t.tag);
        at += 100;
      }
      expect(changes, ['happy'], reason: 'one change, from none to a tag');
    });

    test('a tie, exact or near, never brings up a tag', () {
      // Without a margin, the first label alphabetically would win a tie.
      for (final tie in const [
        {'sad': 0.4, 'angry': 0.4, 'neutral': 0.1},
        {'fear': 0.43, 'disgust': 0.45, 'neutral': 0.1},
        {'neutral': 0.45, 'surprise': 0.44},
      ]) {
        final t = ExpressionTagger();
        feed(t, 0, 50, (_) => tie);
        expect(t.tag, isNull, reason: '$tie');
      }
    });

    test('a close call goes to the happier expression', () {
      // The SDK scores a smile as contempt too: a tie is a smile.
      for (final (tie, tag) in const [
        ({'happy': 0.4, 'contempt': 0.4, 'neutral': 0.1}, 'happy'),
        ({'contempt': 0.42, 'happy': 0.39}, 'happy'),
        ({'happy': 0.45, 'neutral': 0.45}, 'happy'),
        ({'fear': 0.44, 'surprise': 0.42}, 'surprise'),
      ]) {
        final t = ExpressionTagger();
        feed(t, 0, 50, (_) => tie);
        expect(t.tag, tag, reason: '$tie');
      }
    });

    test('a shown #contempt gives way to a tied smile', () {
      final t = ExpressionTagger();
      var at = feed(t, 0, 20, (_) => const {'contempt': 0.6, 'happy': 0.1});
      expect(t.tag, 'contempt');
      at = feed(t, at, 30, (_) => const {'contempt': 0.42, 'happy': 0.41});
      expect(t.tag, 'happy');
      // A clear lead is still a clear lead.
      feed(t, at, 30, (_) => const {'contempt': 0.6, 'happy': 0.2});
      expect(t.tag, 'contempt');
    });

    test('a close call keeps the tag already shown, without blinking', () {
      final t = ExpressionTagger();
      final changes = <String?>[];
      var at = 0;
      void run(int frames, Map<String, double> expr) {
        for (var i = 0; i < frames; i++, at += 100) {
          if (t.add(at, expr, faceOk: true)) changes.add(t.tag);
        }
      }

      run(20, const {'fear': 0.6, 'neutral': 0.2});
      expect(t.tag, 'fear');
      // Disgust (just as unhappy) creeps up to within a hair and stays.
      run(50, const {'fear': 0.44, 'disgust': 0.42});
      expect(t.tag, 'fear');
      // Then clearly overtakes.
      run(30, const {'disgust': 0.55, 'fear': 0.35});
      expect(t.tag, 'disgust');
      expect(changes, ['fear', 'disgust']);
    });

    test('a sustained change switches the tag after the hold', () {
      final t = ExpressionTagger();
      var at = feed(t, 0, 20, (_) => calm);
      expect(t.tag, 'neutral');
      at = feed(t, at, 30, (_) => surprised);
      expect(t.tag, 'surprise');
    });

    test('hides the tag when nothing scores clearly', () {
      final t = ExpressionTagger();
      var at = feed(t, 0, 20, (_) => calm);
      expect(t.tag, 'neutral');
      at = feed(t, at, 30, (_) => unsure);
      expect(t.tag, isNull);
    });

    test('keeps the tag through a short dropout, drops it after 1 s', () {
      final t = ExpressionTagger();
      var at = feed(t, 0, 20, (_) => surprised);
      expect(t.tag, 'surprise');
      at = feed(t, at, 5, (_) => surprised, faceOk: false);
      expect(t.tag, 'surprise', reason: 'half a second without a face');
      at = feed(t, at, 20, (_) => surprised);
      expect(t.tag, 'surprise');
      at = feed(t, at, 11, (_) => surprised, faceOk: false);
      expect(t.tag, isNull, reason: 'a second without a face');
      // Back again: it waits for the hold, rather than flashing a stale tag.
      at = feed(t, at, 3, (_) => calm);
      expect(t.tag, isNull);
      feed(t, at, 10, (_) => calm);
      expect(t.tag, 'neutral');
    });

    test('an empty score map counts as no face', () {
      final t = ExpressionTagger();
      var at = feed(t, 0, 20, (_) => calm);
      at = feed(t, at, 11, (_) => const {});
      expect(t.tag, isNull);
    });

    test('reset forgets the tag and the smoothing', () {
      final t = ExpressionTagger();
      final at = feed(t, 0, 20, (_) => surprised);
      expect(t.tag, 'surprise');
      t.reset();
      expect(t.tag, isNull);
      feed(t, at, 10, (_) => calm);
      expect(t.tag, 'neutral', reason: 'no surprise left in the average');
    });

    test('only the eight SDK categories can become a tag', () {
      final t = ExpressionTagger();
      // The bridge names unexpected types "unspecified" or "unknown<n>".
      feed(
        t,
        0,
        20,
        (_) => const {'unspecified': 0.9, 'unknown12': 0.95, 'neutral': 0.1},
      );
      expect(t.tag, isNull);
      final t2 = ExpressionTagger();
      feed(t2, 0, 20, (_) => const {'unknown12': 0.95, 'happy': 0.5});
      expect(t2.tag, 'happy');
    });

    test('drops the tag when expressions stop updating, face or not', () {
      final t = ExpressionTagger();
      var at = 0;
      for (var i = 0; i < 20; i++, at += 100) {
        t.add(at, surprised, faceOk: true, exprAtMs: at);
      }
      expect(t.tag, 'surprise');
      // The bridge keeps resending the last scores; the SDK went quiet at
      // [at]. Up to 3 s that's normal, after that the scores are stale.
      final quietFrom = at;
      for (; at < quietFrom + 3000; at += 100) {
        t.add(at, surprised, faceOk: true, exprAtMs: quietFrom);
      }
      expect(t.tag, 'surprise', reason: '3 s without a new sample');
      for (; at < quietFrom + 4200; at += 100) {
        t.add(at, surprised, faceOk: true, exprAtMs: quietFrom);
      }
      expect(t.tag, isNull, reason: 'stale for over a second');
      // Fresh samples again: back after the usual hold.
      for (var i = 0; i < 10; i++, at += 100) {
        t.add(at, surprised, faceOk: true, exprAtMs: at);
      }
      expect(t.tag, 'surprise');
    });

    test('a clock that steps back neither stalls nor flips the tag', () {
      final t = ExpressionTagger();
      var at = feed(t, 10000, 20, (_) => calm);
      expect(t.tag, 'neutral');
      // The wall clock jumps back 5 s mid-change.
      at = feed(t, at, 4, (_) => surprised);
      at = feed(t, at - 5000, 30, (_) => surprised);
      expect(t.tag, 'surprise', reason: 'switches within the usual time');
      // And back mid-dropout: still dropped after a second.
      at = feed(t, at, 5, (_) => surprised, faceOk: false);
      feed(t, at - 5000, 11, (_) => surprised, faceOk: false);
      expect(t.tag, isNull);
    });

    test('add reports exactly when the tag changes', () {
      final t = ExpressionTagger();
      var changes = 0;
      var at = 0;
      for (var i = 0; i < 20; i++) {
        if (t.add(at, calm, faceOk: true)) changes++;
        at += 100;
      }
      expect(changes, 1);
    });
  });

  group('CameraStampSlot', () {
    Future<void> pump(WidgetTester tester, String? tag, {bool still = false}) =>
        tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: still),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: SizedBox(
                  width: 146,
                  height: 80,
                  child: CameraStampSlot(
                    tag: tag,
                    stressTags: const [
                      'surprise',
                      'fear',
                      'contempt',
                      'disgust',
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    Color inkOf(WidgetTester tester) {
      final block = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ExpressionStamp),
              matching: find.byType(Container),
            ),
          )
          .first;
      return (block.decoration! as BoxDecoration).color!;
    }

    testWidgets('red ink for expressions the score counts, teal otherwise', (
      tester,
    ) async {
      await pump(tester, 'fear');
      await tester.pumpAndSettle();
      expect(find.text('#fear'), findsOneWidget);
      expect(inkOf(tester), SusColors.tomatoDeep);

      await pump(tester, 'happy');
      await tester.pumpAndSettle();
      expect(find.text('#happy'), findsOneWidget);
      expect(find.text('#fear'), findsNothing);
      expect(inkOf(tester), SusColors.teal);
    });

    testWidgets('VoiceOver reads the expression, not "number fear"', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, 'fear');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Expression: fear'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('stamps in, and fades out when the tag goes', (tester) async {
      await pump(tester, null);
      expect(find.byType(ExpressionStamp), findsNothing);
      await pump(tester, 'surprise');
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(ExpressionStamp), findsOneWidget);
      await pump(tester, null);
      await tester.pumpAndSettle();
      expect(find.byType(ExpressionStamp), findsNothing);
    });

    testWidgets('no motion with Reduce Motion on', (tester) async {
      await pump(tester, null, still: true);
      await pump(tester, 'surprise', still: true);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byType(ExpressionStamp), findsOneWidget);
    });

    testWidgets('fits the slot, tilt and all, even with big text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MediaQuery.fromView(
          view: tester.view,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 120,
                height: 80,
                child: CameraStampSlot(
                  tag: 'contempt',
                  stressTags: const ['contempt'],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final slot = tester.getRect(find.byType(CameraStampSlot));
      final stamp = tester.getRect(find.byType(ExpressionStamp));
      expect(stamp.width, lessThanOrEqualTo(slot.width + 0.01));
      expect(stamp.right, closeTo(slot.right, 0.01), reason: 'right-aligned');
      expect(stamp.top, closeTo(slot.top, 0.01), reason: 'top-aligned');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a camera problem takes the tag\'s place, in mustard', (
      tester,
    ) async {
      Future<void> show(String? tag, String? issue) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 170,
              height: 80,
              child: CameraStampSlot(
                tag: tag,
                stressTags: const ['fear'],
                issue: issue == null ? null : IssueStamp(text: issue),
              ),
            ),
          ),
        ),
      );
      await show('fear', null);
      await tester.pumpAndSettle();
      await show('fear', 'Hold still');
      expect(tester.hasRunningAnimations, isTrue, reason: 'stamped in');
      await tester.pumpAndSettle();
      expect(find.text('Hold still'), findsOneWidget);
      expect(find.byType(ExpressionStamp), findsNothing);
      final block = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(IssueStamp),
              matching: find.byType(Container),
            ),
          )
          .first;
      expect((block.decoration! as BoxDecoration).color, SusColors.mustard);
      await show('fear', null);
      await tester.pumpAndSettle();
      expect(find.byType(IssueStamp), findsNothing);
      expect(find.text('#fear'), findsOneWidget);
    });

    test('every camera problem has a stamp that fits and lands tilted', () {
      const codes = [
        'TOO_DARK',
        'TOO_BRIGHT',
        'NO_FACE_FOUND',
        'MULTIPLE_FACES_FOUND',
        'FACE_TOO_FAR',
        'FACE_TOO_CLOSE',
        'FACE_NOT_CENTERED',
        'FACE_NOT_FORWARD',
        'EXCESSIVE_MOTION',
        'FRAME_RATE_TOO_LOW',
        'SOMETHING_NEW',
      ];
      for (final code in codes) {
        final issue = SignalIssue.fromCode(code)!;
        // The longest, "Too many faces", is 14 characters.
        expect(issue.stamp.length, lessThanOrEqualTo(14), reason: code);
        expect(IssueStamp.tiltDegrees(issue.stamp), isNot(0), reason: code);
      }
    });

    test('each tag keeps its own tilt and worn pattern', () {
      expect(ExpressionStamp.tiltDegrees('surprise'), isNot(0));
      expect(ExpressionStamp.seedFor('fear'), ExpressionStamp.seedFor('fear'));
      expect(
        ExpressionStamp.seedFor('fear'),
        isNot(ExpressionStamp.seedFor('sad')),
      );
    });
  });
}
