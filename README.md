# Sus-o-meter

**A camera-and-voice party game for iPhone.** One player sits in the hot seat, friends ask
questions out loud, and the app reads the player's live pulse, blinks, expressions and hesitation
with the [Presage SmartSpectra SDK](https://smartspectra.presagetech.com/docs/swift/), then
delivers a 70s game-show verdict: **Legit / Hmm… / Sus!**

> **It reads stress, not truth.** Sus-o-meter is an entertainment game. It is not a lie
> detector and not a medical device. A racing pulse means "nervous", never "guilty".

Built for the DEV [Presage SmartSpectra SDK Challenge](https://dev.to/challenges/presage-2026-11-04)
(`#presagechallenge`). Design and build spec: [`docs/SPEC.md`](docs/SPEC.md). Mockups:
[`docs/design/`](docs/design/).

## Contents

- [How a game goes](#how-a-game-goes)
- [Requirements](#requirements)
- [Setup](#setup)
- [Your Presage API key](#your-presage-api-key)
- [Permissions](#permissions)
- [Privacy and data handling](#privacy-and-data-handling)
- [How the score works](#how-the-score-works)
- [How turn-taking works](#how-turn-taking-works)
- [Architecture](#architecture)
- [Proof Panel](#proof-panel)
- [Development](#development)
- [Known limitations](#known-limitations)
- [Credits](#credits)

## How a game goes

1. **Lobby:** add 2–8 contestants (or 1+ in *Solo · host asks*), pick 3/5/7 questions per turn
   and a Mild or Spicy deck. The **?** next to the gear explains the score and the #tags.
2. **Consent:** the phone goes to the hot-seat player, who reads what the camera measures and
   what happens to the data, then taps *I agree, measure me* or *Skip my turn*.
3. **Calibrate:** about 20 s of sitting still, then 3 easy warm-up questions read by the host,
   each asking for a sentence. Everyone gets the same three kinds, in order: something recent
   ("Tell me what you had for breakfast"), a "Have you ever…?" with an easy, true answer, like the
   real questions without the stakes, and a light either/or ("Cats or dogs? Tell me why"). A
   skipped one is replaced by another of the same kind; skip that too and it moves on. This learns *your* normal pulse, blink rate,
   expressions and how fast you usually answer, while talking like you will in the real
   questions. It ends between warm-ups, never while the host is reading one or you're answering.
4. **Ask:** a friend asks a question out loud; it appears on screen as they speak. In solo mode
   the host reads one from the deck, and it stays on screen until you start answering or tap
   *Ready to answer*. Solo questions get hotter through the turn and end on the hottest, the same
   way for every player; "someone in this room" questions only come up when others are playing.
5. **Answer:** the player answers out loud and smashes *Final answer* (or just stops talking).
6. **Call it!:** everyone else votes Legit or Sus *before* the reveal.
7. **Countdown → Verdict:** drumroll, 3-2-1, then the scoreboard, applause meter and what moved.
8. **Leaderboard:** Best poker face, Most sus, Best lie detector, Biggest spike, and a Replay of
   every question. *Wipe everything* clears it all.

## Requirements

- A Mac with **Xcode 26 or later** (the SmartSpectra binary is built with Swift 6.2)
- An **iPhone on iOS 17+** (the simulator has no camera)
- **Flutter 3.38+** (tested with 3.47.9, which uses Swift Package Manager; no CocoaPods)
- A **Presage API key** (free) from [physiology.presagetech.com](https://physiology.presagetech.com)
- An internet connection when a game starts (the SDK signs in; video stays on the phone, but the
  SDK sends pulse and HRV values to Presage, see [Privacy](#privacy-and-data-handling))

## Setup

```bash
git clone https://github.com/littlepaprikalab/susometer.git
```
```bash
cd susometer && flutter pub get
```
```bash
open ios/Runner.xcworkspace
```

In Xcode, select the **Runner** target → **Signing & Capabilities** and choose your team (change
the bundle identifier if `com.littlepaprikalab.susometer` is taken). Xcode downloads the
SmartSpectra Swift package (~60 MB) the first time. Then connect your iPhone and run:

```bash
flutter run
```

On first launch, open **Settings** (gear icon), paste your Presage key and tap **Save & test**.
Tapping *Start the show* without a key opens Settings for you.

**Optional, debug builds only:** to skip pasting the key during development, copy
`ios/Flutter/Secrets.example.xcconfig` to `ios/Flutter/Secrets.xcconfig` (gitignored) and set
`PRESAGE_API_KEY`. On the first debug launch with an empty Keychain it's copied into the
Keychain once. Release builds never read it.

## Your Presage API key

1. Register at [physiology.presagetech.com](https://physiology.presagetech.com/auth/register)
   and confirm your email.
2. Log in and copy your API key from the portal.
3. In the app: **Settings → Presage API key → Paste → Save & test**. The chip turns
   **Connected** when Presage accepts it, or **Key rejected** with the SDK error code.

The key is stored in the iPhone's **Keychain** (this device only, after first unlock). Dart sends
it to Swift once, on save; it never comes back (Settings only shows `••••1a2b`). It's used only to
sign in to Presage. **Remove** deletes it; deleting the app does too (iOS keeps Keychain items
after an uninstall, so the app wipes any leftover key on its first launch after a fresh install).

For production, Presage's OAuth (App Attest) option would remove the key entirely; only
`configure()` in `PresageBridge.swift` and `Info.plist` would change.

## Permissions

| Permission | Needed? | Used for |
|---|---|---|
| Camera | **Required** | SmartSpectra reads pulse, blinks, expressions and talking from the front camera |
| Microphone | Optional | Hears the question and the answer |
| Speech recognition | Optional | Turns speech into on-screen text, **on this phone only** |

Without the mic you can still play: tap *Done asking*, then *Final answer*, with no transcripts.
If on-device recognition isn't available for your language, the app never falls back to Apple's
servers; it switches to tap-to-advance instead.

## Privacy and data handling

| Data | Where | Retention | Shared? |
|---|---|---|---|
| Camera video | Processed on-device by SmartSpectra | Never stored | Never |
| Vitals and face signals | In-memory game state | Until the game ends or *Wipe everything* | Not by the app. The SDK sends pulse and HRV values to Presage (next rows) |
| Audio | On-device Apple speech recognition (`requiresOnDeviceRecognition = true`) | Never stored | Never |
| Transcripts (questions and answers) | In memory | Until *Wipe* or the app closes | Never. Not on the share card |
| Names and scores | In memory | Until *Wipe* or the app closes | Only if you tap *Share results* (an image with names, scores and awards) |
| SmartSpectra telemetry | SDK | n/a | **Off by default.** Opt in under Settings → SDK telemetry: an anonymous per-session diagnostic summary (no video, no vitals values, no identifiers) |
| Presage API key | iOS Keychain, this device only | Until *Remove* or the app is deleted | Sent only to Presage to start a session |
| SmartSpectra sign-in | The SDK contacts Presage with the key to start a session | n/a | Required by the SDK |
| SmartSpectra LLM Insights | The SDK sends buffered pulse rate and HRV values (no video) to Presage, which asks an LLM for a "vitals check-in" | n/a | **On, and the SDK has no switch for it.** It fires on its own once the pulse is stable (~15 s in) and every 60 s after that. The app never asks for one and never shows the answer |

- **No accounts, no analytics, no backend, no disk persistence.** Game data never touches
  `UserDefaults` or files. The only thing written outside the Keychain is one boolean used to
  detect a fresh install. Settings toggles reset every launch.
- **Consent** is collected per player, per game, from the person being measured (screen 2).
  *Skip my turn* is always available.
- **LLM Insights (on, and can't be turned off).** SmartSpectra 3.4.0 auto-fires "vitals
  check-ins": once the pulse has a stable reading (about 15 s in), then when HRV does, then
  every 60 s, it sends the buffered pulse rate and HRV values, a fixed prompt and a session ID
  to Presage, which forwards them to an LLM. Video and face images are never sent. The SDK has
  no setting to turn this off (`enableTelemetry` is a separate thing), so the only way to stop it
  would be to stop measuring the pulse. An early build assumed leaving out breathing metrics
  prevented it; on a device it didn't. The consent screen now says so, and the Proof Panel shows
  each insight the SDK publishes (**LLM INSIGHT ×n**, and whether it was answered or failed),
  never its text. Sources: Presage's
  [LLM insights docs](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/docs/llm-insights/index.md)
  and [data types](https://github.com/Presage-Security/SmartSpectra/blob/v3.4.0/docs/data-types.md#insight).
- See Presage's [telemetry and privacy page](https://smartspectra.presagetech.com/docs/telemetry-and-privacy).

## How the score works

The app explains this in plainer words too: tap **?** next to the gear in the lobby for
*How it's scored* (the four signals and their weights, the verdict bands, No clean read and the
#tags). Its numbers come from [`ScoringConfig`](lib/game/scoring_config.dart), so it always
matches the scoring below.

Everything is relative to **your own baseline** from calibration: median pulse, your blink rate
while chatting through the warm-ups, the strongest each stress expression got in the warm-ups,
and your warm-up answer speed. For each question the app measures the window from when the
question starts until the answer ends (at least 12 s after the question ends) and normalizes
four signals to 0–1. Each one counts **only what's bigger than your own normal wobble**, so a
calm, honest answer scores near 0:

| Signal | Formula | Weight |
|---|---|---|
| Pulse | heartbeat shape compared with your earlier answers, first spread free ([below](#pulse-from-heartbeats)), or if the beats aren't good enough, (mean confident pulse − your baseline) ÷ 15 BPM | 0.45 |
| Blinks | (blinks − expected − chance) ÷ (0.6 × expected), where expected = your chat rate × window (at least 6/min) and chance = √expected, widened for how long your baseline was counted. Or 0.6 for a blink "freeze" longer than chance would explain | 0.25 |
| Expressions | how far surprise / fear / contempt / disgust goes above its warm-up peak, ÷ 0.3 | 0.15 |
| Hesitation | (time to start answering − your usual − 1 s) ÷ 3 s | 0.15 |

`score = round(100 × (weighted sum)^0.8)`. **Legit** under 35, **Hmm…** 35–59, **Sus!** 60+.

Why each part is built that way:

- **Blinks** come at random, so a 15 s window's count wobbles by about its square root even when
  nothing changed. Only blinks beyond that count. People also blink more talking than sitting
  still, so the baseline is the warm-up chat, not the still part. A **freeze** counts only if no
  blink came for so long that, at your rate, a gap like it would turn up by chance less than 1 time
  in 20 (at 17 blinks a minute that's longer than a 15 s window, so it can't happen; a fast
  blinker can freeze in about 8 s). Never under 6 s, and not below 12 blinks a minute.
- **Expressions:** the highest moment of an answer is always above your *average*, so the
  comparison is with your *highest* moment in the warm-ups, smoothed over 1 s. Each of the four
  counts on its own score; happy, sad, angry and neutral don't count. Presage publishes no
  accuracy figures for its expression scores.
- **Hesitation:** real questions take a little longer to think about than warm-ups, so the first
  extra second is free.
- **Pulse:** beats within one robust spread of your other answers are your normal wobble.

`test/calm_answers_test.dart` checks the zero point by simulation: thousands of made-up players
answer through the real code. With nothing changed since the warm-ups, about 93% come out Legit
and none Sus. With an ordinary honest answer (longer to think about, more talking, a smile),
about 85% are Legit and none Sus. A clear stress reaction (pulse up 12 BPM, a 3 s pause, a blink
burst, a burst of surprise) is still about 87% Sus. Before the zero-point fixes (SPEC decision 65)
the honest answer was Sus a third of the time. The noise levels in the simulation are assumptions,
not measured on a device.

**No fake verdicts:** pulse samples below 40% confidence, or that arrive while SmartSpectra's
validation isn't OK, are ignored. If less than 60% of the window has a present face and a fresh
confident pulse, the result is **No clean read** with the real reasons (e.g. "The camera lost
Sam's face for about 5 seconds") and an *Ask it again* button. Every constant lives in
[`ScoringConfig`](lib/game/scoring_config.dart) for tuning.

**Expression #tag.** While the camera measures, the player's strongest expression is stamped in
its top-right corner as a #tag, in the SDK's own words (#surprise, #happy, #neutral…). SmartSpectra
gives a score per expression rather than one label, so the tag is the top score, smoothed over
about 0.6 s and changed only once a new one has clearly led for 0.7 s, so it doesn't flicker
and a tie never shows an arbitrary expression. Red ink marks the four that move the score, teal
the rest. It's hidden when no expression scores clearly,
there's no usable face, or the SDK stops sending new expression readings. It's the raw reading, not compared to the player's normal, so it's for
show; the score uses the comparison. Logic: [`lib/game/expression_tag.dart`](lib/game/expression_tag.dart).

### Pulse from heartbeats

SmartSpectra's pulse number is a 12-second average, so a reaction lasting a few seconds is
smeared and arrives late. The app also gets the SDK's pulse waveform and finds each heartbeat
itself ([`lib/game/beats.dart`](lib/game/beats.dart)):

1. Keep only stretches of the waveform where validation was OK, with no gap over 0.3 s.
2. Band-pass filter it to about 42–210 BPM, so breathing drift and fast noise drop out.
3. Each peak at least 0.33 s after the previous one is a beat, timed between samples.
4. Intervals far from their neighbours (a missed or extra beat) are thrown out.

That gives heart rate beat by beat, with a lag of about one beat. For each question, the app reads
three things from it, compared with your level in the 5 s just before the question:

- **Rise:** the highest point in the window (smoothed over 3 s).
- **Ran high:** the mean over the whole window.
- **Early slowdown:** the lowest point in the 6 s after the question ends. A brief slowdown is the
  heart-rate response that concealed-information studies most often report.

Each one is compared with the same player's **warm-ups and earlier questions**: how far it is above
their median, in robust spreads (1.4826 × median absolute deviation, at least 4 / 3 / 3 BPM). The
first spread is their normal wobble and counts for nothing; 2.5 spreads counts in full. The pulse part is 0.4 × rise + 0.4 × ran high + 0.2 × slowdown. So a
question is sus when your heart did something your other answers didn't, and a turn that's tense
throughout doesn't make every question look sus.

The beats are used only when they cover at least 60% of the window, their 12 s average agrees with
the SDK's pulse within 8 BPM (allowing the SDK's reading to arrive up to 6 s late), and at least
2 of your warm-ups had good beats (earlier questions add to the comparison but can't replace the
warm-ups, so a turn stays on one scale). Otherwise
the score uses the SDK-mean formula in the table. The Proof Panel shows which one each score used
and why.

## How turn-taking works

The host is the phone's voice: a British woman's, the most natural one installed (a downloaded
premium voice such as Serena sounds best; Settings > Accessibility > Spoken Content > Voices).
Speaker separation uses SmartSpectra's **talking** detection instead of diarization: speech
while the hot-seat player isn't talking is the question; speech while they are is the answer.

- **Question ends** when the player starts talking, or after 1.5 s of silence following the
  asker (the host then asks "{name}, your answer?"), or with *Too loud? Tap when done asking*.
- **Answer ends** with *Final answer*, or 4 s after the player stops talking.
- **Half-duplex:** recognition is muted while the host speaks or a sound plays, and for 150 ms
  after, so the transcript never contains the host.

Details: [`lib/voice/turn_detector.dart`](lib/voice/turn_detector.dart) and SPEC §7.

## Architecture

```mermaid
flowchart LR
  subgraph Flutter["Flutter (Dart)"]
    UI["Screens<br/>lobby · calibrate · ask · answer · verdict …"]
    GC["GameController<br/>state machine · scoring · turn detection"]
    UI <--> GC
  end
  subgraph Swift["iOS (Swift)"]
    PB["PresageBridge"]
    CP["CameraPreviewView<br/>(platform view)"]
    SB["SpeechBridge<br/>on-device speech · host voice · sounds"]
    DB["DeviceBridge<br/>permissions · keep-awake · share"]
    KC[("Keychain")]
  end
  SDK["SmartSpectra SDK 3.4.0<br/>pulse · HRV · blinks · talking · expressions · validation"]
  GC -- "MethodChannel sus/presage" --> PB
  PB -- "EventChannel sus/presage/stream (~10 Hz)" --> GC
  GC -- "sus/speech + stream" --> SB
  GC -- "sus/device" --> DB
  UI -. "UiKitView sus/camera_preview" .-> CP
  PB --> SDK
  CP --> SDK
  PB --> KC
```

- [`ios/Runner/Presage/PresageBridge.swift`](ios/Runner/Presage/PresageBridge.swift) configures
  the SDK, observes it with `withObservationTracking`, and streams snapshots (pulse + confidence,
  HRV, the pulse waveform with SDK timestamps, blink/talk edges, expressions, validation, status,
  errors).
- [`ios/Runner/Voice/SpeechBridge.swift`](ios/Runner/Voice/SpeechBridge.swift) runs
  `SFSpeechRecognizer` on-device only, plus the host's `AVSpeechSynthesizer` voice and sounds.
- [`lib/game/`](lib/game/) holds the game logic, which is pure Dart and unit-tested.

## Proof Panel

For judges and the demo video: turn on **Settings → Proof panel**, or long-press the lobby logo
(or tap it 5 times). On every measuring screen it overlays the raw SmartSpectra stream (pulse and
confidence, RMSSD and confidence, blink and talking flags, top expression, validation code and
hint, SDK status, telemetry state), the baseline, and the timing markers `tQ0 tQ1 tA0 tA1`.
It also shows the heartbeat check: waveform samples per second and their confidence; heart rate,
beat-to-beat RMSSD and coverage from the beats the app found over the last 12 s; and, for the last
scored question, whether the pulse part came from beats (with each part's 0–1 score and the raw
BPM) or the SDK mean (with the reason). On a device, the beat rate should track the SDK's pulse and
the beat RMSSD should be near the SDK's.
**Settings → Signal check** opens a bare screen with the camera, live signals and the transcript
side by side.

## Development

```bash
flutter analyze
```
```bash
flutter test
```

Tests run without a device. They cover scoring and turn detection with synthetic SmartSpectra
streams, full games on fake time (controller and through the real screens at 390×844 with the
real fonts), accessibility actions and color contrast.

- **Swift type check on Linux/macOS without Xcode:** `tool/swift_typecheck/run.sh` checks the
  native bridge against stand-in modules (the SmartSpectra one mirrors the 3.4.0 interface).
  Needs a Swift 6.2 toolchain. It's a quick sanity check, not a substitute for an Xcode build.
- **Sounds and icon** are generated: `python3 tool/gen_sfx.py`, `python3 tool/gen_icon.py`
  (needs Pillow).
- **Claude Code cloud sessions** install Flutter through `.claude/hooks/session-start.sh`.
- Build decisions are logged at the end of [`docs/SPEC.md`](docs/SPEC.md).
- On-device test script: [`docs/DEVICE_CHECKLIST.md`](docs/DEVICE_CHECKLIST.md).

## Known limitations

- **It measures stress reactions, not honesty**, and only roughly: a webcam-grade, entertainment
  estimate. Not medical, not diagnostic, not a lie detector.
- **Light and position matter:** dim rooms, a bright window behind you, moving the phone, or a
  second face in frame all reduce signal quality. The app pauses and says why rather than guess.
- **Noise:** loud rooms make transcripts unreliable; use *Too loud? Tap when done asking*.
- **Talking detection** comes from the camera, so a mumbled answer may need the *Final answer* tap.
- **HRV** needs about 60 s of measurement; it's shown, not scored.
- **Heartbeats from the waveform are untested on a device so far.** They're checked against the
  SDK's pulse on every question, and the score falls back to the SDK mean when they disagree.
  The shape constants (`ScoringConfig`) still need tuning from real play.
- **Network:** the SDK must sign in to start a session (E5 explains if it can't).
- **Languages:** transcripts need on-device recognition for the iPhone's language; otherwise the
  game is tap-to-advance.
- Heavy use warms the phone; between turns the app suggests a breather if iOS reports it's hot.

## Credits

- **Presage SmartSpectra SDK** for all vitals and face signals.
- **Fonts:** [Bowlby One SC](https://fonts.google.com/specimen/Bowlby+One+SC) by Vernon Adams and
  [Work Sans](https://fonts.google.com/specimen/Work+Sans) by Wei Huang, both under the SIL Open
  Font License ([`assets/fonts/`](assets/fonts/)).
- **Sound effects:** synthesized for this project by [`tool/gen_sfx.py`](tool/gen_sfx.py) and
  released under CC0. No third-party samples.
- Built with Flutter and Swift. Design and code written with Claude Code.
