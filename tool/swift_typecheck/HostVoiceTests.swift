// Behaviour tests for HostVoice, the host's voice choice in
// ios/Runner/Voice/SpeechBridge.swift (SPEC.md decisions 33 and 73).
// run.sh builds them with HostSpeechTests.swift, whose main runs them.
//
// The voices below use the identifiers iOS reports, so the filters on
// identifier prefixes are checked against real shapes.

import Foundation

private var failures = 0

private func check(_ ok: Bool, _ what: String, line: Int = #line) {
  if !ok {
    failures += 1
    print("FAIL line \(line): \(what)")
  }
}

private typealias V = HostVoice.Candidate

// en-US
private let samantha = V(
  identifier: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: 1,
  gender: .female)
private let avaPremium = V(
  identifier: "com.apple.voice.premium.en-US.Ava", name: "Ava", language: "en-US", quality: 3, gender: .female)
private let fred = V(
  identifier: "com.apple.speech.synthesis.voice.Fred", name: "Fred", language: "en-US", quality: 1,
  gender: .male)
// en-GB
private let daniel = V(
  identifier: "com.apple.voice.compact.en-GB.Daniel", name: "Daniel", language: "en-GB", quality: 1,
  gender: .male)
private let jamiePremium = V(
  identifier: "com.apple.voice.premium.en-GB.Jamie", name: "Jamie", language: "en-GB", quality: 3,
  gender: .male)
private let kate = V(
  identifier: "com.apple.voice.compact.en-GB.Kate", name: "Kate", language: "en-GB", quality: 1, gender: .female)
private let martha = V(
  identifier: "com.apple.ttsbundle.siri_Martha_en-GB_compact", name: "Martha", language: "en-GB", quality: 1,
  gender: .female)
private let kateEnhanced = V(
  identifier: "com.apple.voice.enhanced.en-GB.Kate", name: "Kate", language: "en-GB", quality: 2,
  gender: .female)
private let serenaPremium = V(
  identifier: "com.apple.voice.premium.en-GB.Serena", name: "Serena", language: "en-GB", quality: 3,
  gender: .female)
private let flo = V(
  identifier: "com.apple.eloquence.en-GB.Flo", name: "Flo", language: "en-GB", quality: 1, gender: .female)
private let personal = V(
  identifier: "com.apple.speech.personalvoice.1", name: "My Voice", language: "en-GB", quality: 3, gender: .female,
  isNoveltyOrPersonal: true)
// Not English
private let amelie = V(
  identifier: "com.apple.voice.premium.fr-CA.Amelie", name: "Amelie", language: "fr-CA", quality: 3,
  gender: .female)

private func pick(
  _ voices: [V], user: String = "en-US", systemDefault: String? = samantha.identifier
) -> String? {
  HostVoice.best(voices, userLanguage: user, systemDefault: systemDefault)
    .map { voices[$0].identifier }
}

enum HostVoiceTests {
  /// Runs every case; returns the number of failed checks.
  static func run() -> Int {
    britishFemaleBeatsEveryoneElse()
    bestBritishFemaleWins()
    siriBreaksTies()
    roboticVoicesNeverPicked()
    fallsBackToBestEnglish()
    nothingUsable()
    voicesWithNoGender()
    firstInListWinsATie()
    largeVoiceList()
    return failures
  }

  /// A standard British female voice beats premium American and British male
  /// ones, in any English locale.
  static func britishFemaleBeatsEveryoneElse() {
    let voices = [avaPremium, jamiePremium, samantha, daniel, kate]
    check(pick(voices) == kate.identifier, "British female over premium others (en-US)")
    check(
      pick(voices, user: "en-AU", systemDefault: nil) == kate.identifier,
      "British female over premium others (en-AU)")
    check(
      pick(voices, user: "en-GB", systemDefault: daniel.identifier) == kate.identifier,
      "British female over the en-GB default, Daniel")
  }

  /// Among British female voices, premium, then enhanced, then standard.
  static func bestBritishFemaleWins() {
    check(
      pick([kate, martha, kateEnhanced, serenaPremium, avaPremium]) == serenaPremium.identifier,
      "premium Serena")
    check(pick([serenaPremium, kateEnhanced, kate]) == serenaPremium.identifier, "order doesn't matter")
    check(pick([kate, kateEnhanced, martha]) == kateEnhanced.identifier, "enhanced over standard")
  }

  /// At the same quality, the Siri-derived voice, whatever the list order.
  static func siriBreaksTies() {
    check(pick([kate, martha]) == martha.identifier, "Martha over Kate")
    check(pick([martha, kate]) == martha.identifier, "Martha over Kate, reversed")
  }

  /// Novelty, personal and Eloquence voices, some of them British and female.
  static func roboticVoicesNeverPicked() {
    check(pick([flo, personal, samantha]) == samantha.identifier, "no Flo or personal voice")
    check(pick([fred, flo]) == nil, "only robotic voices: none")
  }

  /// No British female voice: the best English one, as before decision 73.
  static func fallsBackToBestEnglish() {
    check(pick([samantha, daniel, avaPremium, amelie]) == avaPremium.identifier, "premium first")
    check(pick([daniel, samantha]) == samantha.identifier, "en-US user: Samantha")
    check(
      pick([samantha, daniel], user: "en-GB", systemDefault: daniel.identifier)
        == daniel.identifier, "en-GB user: Daniel")
    check(
      pick([daniel, jamiePremium, samantha], user: "en-GB", systemDefault: daniel.identifier)
        == jamiePremium.identifier, "en-GB user: premium Jamie")
  }

  /// A voice that reports no gender: Apple's British women by name only, and
  /// only when British.
  static func voicesWithNoGender() {
    var martha = martha, serena = serenaPremium, daniel = daniel
    martha.gender = .unspecified
    serena.gender = .unspecified
    serena.name = "Serena (Premium)"
    daniel.gender = .unspecified
    let karen = V(
      identifier: "com.apple.voice.compact.en-AU.Karen", name: "Karen", language: "en-AU",
      quality: 1, gender: .unspecified)
    check(pick([avaPremium, martha]) == martha.identifier, "Martha by name")
    check(pick([avaPremium, kate, serena]) == serena.identifier, "Serena (Premium) by name")
    check(pick([avaPremium, daniel]) == avaPremium.identifier, "an unknown British man isn't one")
    var kateAU = kate
    kateAU.language = "en-AU"
    kateAU.gender = .unspecified
    check(pick([avaPremium, kateAU, karen]) == avaPremium.identifier, "only en-GB counts")
    var maleKate = kate
    maleKate.gender = .male
    check(pick([maleKate, samantha]) == samantha.identifier, "a reported gender wins over the name")
  }

  /// Two voices that rank the same: the first in iOS's list, so the choice
  /// doesn't change between lines.
  static func firstInListWinsATie() {
    var kate2 = kate
    kate2.identifier = "com.apple.voice.compact.en-GB.Kate2"
    check(pick([kate, kate2]) == kate.identifier, "first of two equals")
    check(pick([kate2, kate]) == kate2.identifier, "first of two equals, reversed")
  }

  /// iOS 17 lists a few hundred voices; the choice still comes out right
  /// with the British woman last.
  static func largeVoiceList() {
    var voices: [V] = []
    for i in 0..<2000 {
      voices.append(
        V(
          identifier: "com.apple.voice.premium.en-US.Voice\(i)", name: "Voice\(i)",
          language: i % 2 == 0 ? "en-US" : "de-DE", quality: 3, gender: .female))
    }
    voices.append(kate)
    check(pick(voices) == kate.identifier, "found at the end of 2,001 voices")
  }

  static func nothingUsable() {
    check(pick([]) == nil, "no voices")
    check(pick([amelie]) == nil, "no English voices")
  }
}
