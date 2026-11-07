// Behaviour tests for HostSpeech, the half-duplex gate's bookkeeping in
// ios/Runner/Voice/SpeechBridge.swift (SPEC.md decision 71). run.sh builds
// them against the stand-in modules and runs them on Linux.
//
// Each case plays the synthesizer callbacks in an order iOS can produce and
// checks the two things that matter: the mic gate (`busy`) never stays shut
// for good, and it never opens while a stopped utterance might still play.
// Dart's reply to each `speak` must come back exactly once.
//
// main also runs HostVoiceTests.swift, the host's voice choice.

import Foundation

final class Utterance {}

final class Reply {
  private(set) var calls = 0
  func call() { calls += 1 }
}

private var failures = 0

private func check(_ ok: Bool, _ what: String, line: Int = #line) {
  if !ok {
    failures += 1
    print("FAIL line \(line): \(what)")
  }
}

/// Plays Dart's side: replies handed back are "called".
private func deliver(_ replies: [Reply]) { replies.forEach { $0.call() } }

private func deliver(_ ended: (wasOut: Bool, reply: Reply?)) { ended.reply?.call() }

@main
struct HostSpeechTests {
  static func main() {
    normalFinish()
    normalStop()
    stopWithLostCancel()
    stopIgnoredByIOS()
    differentQuestion()
    lostCallbacksOnEveryUtterance()
    identifiersStayUnique()
    longSessionDoesNotGrow()
    let voiceFailures = HostVoiceTests.run()
    if failures + voiceFailures > 0 {
      print("HostSpeech and HostVoice: \(failures + voiceFailures) check(s) failed")
      exit(1)
    }
    print("HostSpeech and HostVoice: all checks passed")
  }

  /// speak → didFinish: gated while speaking, open after, one reply.
  static func normalFinish() {
    var s = HostSpeech<Reply>()
    let u = Utterance(), r = Reply()
    s.spoke(u, reply: r)
    check(s.busy && s.awaited, "gated while the host speaks")
    deliver(s.ended(ObjectIdentifier(u)))
    check(!s.busy, "open after didFinish")
    check(r.calls == 1, "one reply")
    check(s.settle(synthesizerSpeaking: false, lastTry: false) == .done, "nothing to settle")
  }

  /// "Ready to answer": stop → didCancel arrives as it should.
  static func normalStop() {
    var s = HostSpeech<Reply>()
    let u = Utterance(), r = Reply()
    s.spoke(u, reply: r)
    deliver(s.stop())
    check(r.calls == 1, "Dart moves on at the stop")
    check(s.busy, "still gated until the cancel arrives")
    let ended = s.ended(ObjectIdentifier(u))
    check(ended.wasOut && ended.reply == nil, "cancel closes it, no second reply")
    check(!s.busy, "open after didCancel")
    check(s.settle(synthesizerSpeaking: false, lastTry: false) == .done, "settle finds nothing")
  }

  /// The bug: stop, and didCancel never comes. The old counter stayed above
  /// zero for the rest of the app's life.
  static func stopWithLostCancel() {
    var s = HostSpeech<Reply>()
    let u = Utterance(), r = Reply()
    s.spoke(u, reply: r)
    deliver(s.stop())
    check(s.busy, "gated right after the stop")
    check(s.settle(synthesizerSpeaking: false, lastTry: false) == .dropped, "gives up once quiet")
    check(!s.busy, "gate opens without the callback")
    let late = s.ended(ObjectIdentifier(u))
    check(!late.wasOut && late.reply == nil, "a very late cancel is ignored")
    check(r.calls == 1, "still exactly one reply")
  }

  /// Stop lands before the utterance started, and iOS plays it anyway.
  static func stopIgnoredByIOS() {
    var s = HostSpeech<Reply>()
    let u = Utterance(), r = Reply()
    s.spoke(u, reply: r)
    deliver(s.stop())
    check(s.shouldStopAgain(started: ObjectIdentifier(u)), "a stopped utterance that starts is stopped again")
    check(s.busy, "and the mic stays gated while it plays")
    check(s.settle(synthesizerSpeaking: true, lastTry: false) == .stopAgain, "still playing: stop again")
    check(s.busy, "still gated")
    // The second stop lands: didCancel.
    deliver(s.ended(ObjectIdentifier(u)))
    check(!s.busy, "open once it reports back")
    check(r.calls == 1, "one reply")
  }

  /// Solo "Different question": stop the old reading, start the new one at
  /// once. The new reading must hold the gate whatever the old one does.
  static func differentQuestion() {
    var s = HostSpeech<Reply>()
    let old = Utterance(), oldReply = Reply()
    let new = Utterance(), newReply = Reply()
    s.spoke(old, reply: oldReply)
    deliver(s.stop())
    s.spoke(new, reply: newReply)
    // iOS plays the stopped one anyway: stopping again would cut the new one.
    check(!s.shouldStopAgain(started: ObjectIdentifier(old)), "never cut off the new reading")
    check(!s.shouldStopAgain(started: ObjectIdentifier(new)), "a wanted utterance is never stopped")
    check(s.settle(synthesizerSpeaking: true, lastTry: false) == .dropped, "the old one is dropped")
    check(s.busy && s.awaited, "the new reading still holds the gate")
    check(oldReply.calls == 1 && newReply.calls == 0, "only the old reading's reply so far")
    deliver(s.ended(ObjectIdentifier(old)))  // late cancel: ignored
    check(s.busy, "a late cancel for the old one doesn't open the gate")
    deliver(s.ended(ObjectIdentifier(new)))
    check(!s.busy && newReply.calls == 1, "open after the new reading finishes")
  }

  /// Nothing ever reports back, and the synthesizer says it's still busy:
  /// the gate is given up on after the last try, not held for good.
  static func lostCallbacksOnEveryUtterance() {
    var s = HostSpeech<Reply>()
    let u = Utterance(), r = Reply()
    s.spoke(u, reply: r)
    // Dart's speak timeout calls stopSpeaking.
    deliver(s.stop())
    check(s.settle(synthesizerSpeaking: true, lastTry: false) == .stopAgain, "try 1")
    check(s.settle(synthesizerSpeaking: true, lastTry: false) == .stopAgain, "try 2")
    check(s.settle(synthesizerSpeaking: true, lastTry: true) == .dropped, "try 3 gives up")
    check(!s.busy, "gate open after the last try")
    check(r.calls == 1, "one reply")
  }

  /// While an utterance is out, no new object can take its identifier, so a
  /// late callback can't close a different utterance.
  static func identifiersStayUnique() {
    var s = HostSpeech<Reply>()
    var id: ObjectIdentifier?
    do {
      let u = Utterance()
      id = ObjectIdentifier(u)
      s.spoke(u, reply: Reply())
    }
    deliver(s.stop())
    var clash = false
    var keep: [Utterance] = []
    for _ in 0..<2000 {
      let other = Utterance()
      if ObjectIdentifier(other) == id { clash = true }
      keep.append(other)
    }
    check(!clash, "a stopped utterance keeps its identifier while out")
    check(s.busy, "and still holds the gate")
  }

  /// A long show: thousands of lines, half cut off, some with lost callbacks.
  /// Nothing is left behind.
  static func longSessionDoesNotGrow() {
    var s = HostSpeech<Reply>()
    var replies = 0
    for i in 0..<20_000 {
      let u = Utterance(), r = Reply()
      s.spoke(u, reply: r)
      switch i % 4 {
      case 0:
        deliver(s.ended(ObjectIdentifier(u)))
      case 1:
        deliver(s.stop())
        deliver(s.ended(ObjectIdentifier(u)))
      case 2:
        deliver(s.stop())
        _ = s.settle(synthesizerSpeaking: false, lastTry: false)
      default:
        deliver(s.stop())
        _ = s.settle(synthesizerSpeaking: true, lastTry: true)
      }
      replies += r.calls
      if s.busy { check(false, "left something out at line \(i)"); break }
    }
    check(replies == 20_000, "every line got exactly one reply (\(replies))")
  }
}
