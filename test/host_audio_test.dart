import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/audio/host_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sus/speech');
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('say sends the text and completes when the bridge answers', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await MethodChannelHostAudio().say('Sam, your answer?');
    expect(calls.single.method, 'speak');
    expect(calls.single.arguments, {'text': 'Sam, your answer?'});
  });

  test('a lost speech callback times out, stops the voice, and moves on', () {
    fakeAsync((async) {
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        if (call.method == 'speak') return Completer<Object?>().future;
        return Future.value();
      });
      var done = false;
      MethodChannelHostAudio()
          .say('Ask your question!')
          .then((_) => done = true);
      async.elapse(const Duration(seconds: 2));
      expect(done, isFalse);
      async.elapse(MethodChannelHostAudio.speakTimeout('Ask your question!'));
      expect(done, isTrue);
      expect(calls.map((c) => c.method), ['speak', 'stopSpeaking']);
    });
  });

  test('sound effects use the asset file names', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final audio = MethodChannelHostAudio();
    for (final s in Sfx.values) {
      await audio.play(s);
    }
    expect(calls.map((c) => (c.arguments as Map)['name']), [
      'jingle',
      'drumroll',
      'ding_ding',
      'wah_wah',
      'buzzer',
      'applause',
    ]);
  });

  test('audio errors never throw into the game', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'AUDIO');
    });
    final audio = MethodChannelHostAudio();
    await audio.say('Legit!');
    await audio.play(Sfx.buzzer);
    await audio.stopSpeaking();
  });

  test('speak timeout grows with the length of the line', () {
    expect(
      MethodChannelHostAudio.speakTimeout(
        'Here is one for you, Sam. Have you ever re-gifted a present?',
      ),
      greaterThan(MethodChannelHostAudio.speakTimeout('Sus!')),
    );
  });
}
