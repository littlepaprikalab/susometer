---
title: "Sus-o-meter: a game show that reads your pulse, not your mind"
published: false
tags: devchallenge, presagechallenge, flutter, ios
---

*This is a submission for the [Presage SmartSpectra SDK Challenge](https://dev.to/challenges/presage-2026-11-04)*

<!-- Draft. Before publishing: add the demo video link, make the GitHub repo public, upload the cover
image (`docs/cover.png`), and replace anything in [BRACKETS]. Submissions close Nov 22, 11:59 PM PST. -->

## What I Built

**Sus-o-meter** is a camera-and-voice party game for iPhone, styled like a 70s TV game show.
One player sits in the hot seat. Friends ask them questions out loud ("Have you ever re-gifted a
present?"). While they answer, the phone's front camera reads their live pulse, blinks, facial
expressions and how long they hesitate, compares all of it with their own calm baseline, and
the host delivers a verdict on a bulb-framed scoreboard: **Legit**, **Hmm…** or **Sus!**

Before each reveal the rest of the room votes (*Call it!*), so the night ends with awards for
Best poker face, Most sus, Biggest spike and **Best lie detector**: the friend whose calls
matched the meter most often. There's also a solo mode where the host asks the questions.

It reads **stress, not truth**. That line is in the lobby, on every result and in the house
rules, because a racing heart means nervous, not guilty.

## Demo

[DEMO VIDEO LINK]

The video shows the live signals: calibration with a real-time pulse waveform, a question with
live transcription and BPM, the Proof Panel with the raw SmartSpectra values, and the app
recovering when the lights go down.

## Code

[github.com/littlepaprikalab/susometer](https://github.com/littlepaprikalab/susometer). Setup
instructions are in the README: Xcode 26, an iPhone on iOS 17+, Flutter, and a free Presage API
key pasted into the app's Settings screen.

## How It Responds to Human Signals

**Signals used (all live, from the SmartSpectra Swift SDK 3.4.0):** pulse rate with confidence,
HRV (RMSSD, shown in the session view), blinking, talking, facial expressions (surprise, fear,
contempt, disgust), the arterial pressure trace (for the on-screen waveform), and validation
status (face position, lighting, motion).

**How the game reacts in real time:**

- **Calibration** learns each player's normal: a sit-still while the camera finds the pulse (8 to
  20 s), then 3 easy warm-ups the host reads aloud, each answered and then tapped through with
  *Next*. It's locked in once it has 12 s of confident pulse with the face present 80% of the time,
  and the questions start when the room taps *Start the questions*.
- **Questions:** each window scores four signals against that baseline: pulse rise (45%), blink
  rate change or a blink "freeze" (25%), the peak stress expression (15%), and hesitation before
  answering (15%). Each counts only what's bigger than the player's own normal wobble (blinks
  beyond chance, expressions above their warm-up peak, the first second of
  extra thinking free), so a calm, honest answer scores near 0. Then `score = 100 × raw^0.8`.
- **Turn-taking without diarization:** SmartSpectra's **talking** flag tells the app who is
  speaking. Mic speech while the hot-seat player isn't talking is the question; speech while they
  are is the answer. The host names who asks each question, and only taps move the game on
  (*Done asking*, *Final answer*, *Reveal*), because a party is too noisy for silence detection.
  The timing still comes from the voice and the camera: the pause is counted from the asker's last
  words, and a late *Final answer* doesn't stretch the answer.
- **Never a fake verdict:** low-confidence pulse samples, and pulse that arrives more than 2 s
  into a validation problem, are ignored. If less than 60% of the window is clean, the show says
  **No clean read** and explains why with the actual validation hints ("The camera lost Sam's
  face for about 5 seconds"). After a camera restart, a question waits until the pulse is back
  instead of starting blind.
- **Live feedback:** validation issues are stamped right on the camera ("Too dark", with "Face a
  lamp or window." underneath), and the reading resumes when they clear.

**Integration:** Flutter draws the UI, and a thin Swift bridge wraps the SDK. `SmartSpectraSDK` is
`@Observable` and `@MainActor`, so the bridge observes it with `withObservationTracking`
(re-armed on each change), dedupes samples by timestamp, keeps the last valid pulse between
updates, turns blink/talking frames into edges, and streams ~10 Hz snapshots over a Flutter
`EventChannel`. The camera preview is `sdk.imageOutput` in a native platform view. Speech
recognition is a native `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. The host
voice is `AVSpeechSynthesizer`, half-duplexed so the transcript never contains the host. All the
game logic (scoring, turn detection, the state machine) is plain Dart with 100+ tests that use
synthetic SmartSpectra streams.

## Prize Categories

**Most Creative or Delightful Use.** [Optional: why you made it. For example: party games are
about reading your friends, and this one hands that job to an actual pulse signal.] The twist is
that the meter judges the room too: Best lie detector goes to whoever's gut matched the
physiology most often.

## Consent and Data Handling

- **Camera consent is per player, per game,** from the person being measured. Before anyone is
  measured, the phone is passed to them and a screen lists what the front camera reads (pulse,
  blinks, expressions, when they start talking) and what happens to it. They tap *I agree,
  measure me* or *Skip my turn*. Skipping is always available, and iOS asks for camera
  permission too. Nobody is measured without seeing their own face in the preview.
- **Video** is processed on the phone by the SmartSpectra SDK and never stored or sent.
- **Vitals and face signals** live only in memory for the current game. They're wiped when the
  game ends, on *Wipe everything*, or when the app closes. Nothing is written to disk: no
  accounts, no analytics, no backend.
- **Audio** goes only to Apple's on-device speech recognition (`requiresOnDeviceRecognition`). If
  on-device recognition isn't available, the app does **not** fall back to servers; it plays on
  without transcripts. Audio is never recorded. Everyone at the table is told in the lobby that voices
  are transcribed on the phone.
- **Transcripts** (questions and answers) stay in memory for the Replay and are never shared;
  the *Share results* image contains only names, scores and awards.
- **Sharing** only happens if you tap *Share results*, through the iOS share sheet.
- **Presage API key:** stored in the iOS Keychain on this device only, sent only to Presage to
  start a session, removable in Settings, and wiped when the app is deleted.
- **SDK telemetry is off by default** (the SDK's own default is on). Users can opt in in Settings;
  Presage then gets an anonymous per-session diagnostic summary with no video, no vitals values
  and no identifiers ([Presage telemetry docs](https://smartspectra.presagetech.com/docs/telemetry-and-privacy)).
- **LLM Insights: on, from the SDK.** SmartSpectra 3.4.0 auto-fires "vitals check-ins" once the
  pulse is stable and every 60 s: it sends buffered pulse rate and HRV values (never video) to
  Presage, which asks an LLM. The SDK has no switch for this. The app never requests an insight
  and never shows one; the consent screen tells each player, and the Proof Panel shows each
  insight the SDK publishes (answered or failed), never its text.
- **Not medical, not a lie detector.** No diagnosis, no treatment claims, no health advice. It
  measures stress reactions for fun, and only with the hot-seat player's consent.

## Agent Session

<!-- Optional: upload the Claude Code transcript at https://dev.to/agent_sessions/new, embed it
here, and click Make Public. Check it for keys first (no real API key was ever typed into it). -->

[AGENT SESSION EMBED]
