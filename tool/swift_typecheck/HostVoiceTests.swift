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
  identifier: "com.apple.voice.compact.en-US.Samantha", language: "en-US", quality: 1,
  isFemale: true)
private let avaPremium = V(
  identifier: "com.apple.voice.premium.en-US.Ava", language: "en-US", quality: 3, isFemale: true)
private let fred = V(
  identifier: "com.apple.speech.synthesis.voice.Fred", language: "en-US", quality: 1,
  isFemale: false)
// en-GB
private let daniel = V(
  identifier: "com.apple.voice.compact.en-GB.Daniel", language: "en-GB", quality: 1,
  isFemale: false)
private let jamiePremium = V(
  identifier: "com.apple.voice.premium.en-GB.Jamie", language: "en-GB", quality: 3,
  isFemale: false)
private let kate = V(
  identifier: "com.apple.voice.compact.en-GB.Kate", language: "en-GB", quality: 1, isFemale: true)
private let martha = V(
  identifier: "com.apple.ttsbundle.siri_Martha_en-GB_compact", language: "en-GB", quality: 1,
  isFemale: true)
private let kateEnhanced = V(
  identifier: "com.apple.voice.enhanced.en-GB.Kate", language: "en-GB", quality: 2,
  isFemale: true)
private let serenaPremium = V(
  identifier: "com.apple.voice.premium.en-GB.Serena", language: "en-GB", quality: 3,
  isFemale: true)
private let flo = V(
  identifier: "com.apple.eloquence.en-GB.Flo", language: "en-GB", quality: 1, isFemale: true)
private let personal = V(
  identifier: "com.apple.speech.personalvoice.1", language: "en-GB", quality: 3, isFemale: true,
  isNoveltyOrPersonal: true)
// Not English
private let amelie = V(
  identifier: "com.apple.voice.premium.fr-CA.Amelie", language: "fr-CA", quality: 3,
  isFemale: true)

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

  static func nothingUsable() {
    check(pick([]) == nil, "no voices")
    check(pick([amelie]) == nil, "no English voices")
  }
}
