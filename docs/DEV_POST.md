---
title: "Sus-o-meter: a game show that reads your pulse, not your mind"
published: false
tags: devchallenge, presagechallenge, flutter, ios
---

*This is a submission for the [Presage SmartSpectra SDK Challenge](https://dev.to/challenges/presage-2026-11-04)*

<!-- Before publishing:
  1. Make the GitHub repo public (it's private: judges must be able to open it).
  2. Check that the Demo section's list matches what the video shows.
  3. Add the agent session embed, or delete that section.
  4. Add a cover image (a Sus! verdict screenshot works well).
  Deadline: Nov 22, 2026, 11:59 PM PST. -->

## What I Built

**Sus-o-meter** is a party game for iPhone, styled like a 70s TV game show.

One player takes the hot seat with the phone propped up in front of them. A friend asks a
question out loud ("Have you ever re-gifted a present?") and the player answers. While they do,
the front camera reads their **pulse, blinks, facial expressions and how long they hesitated**,
compares all of it with their own calm baseline, and the host announces the verdict on a
bulb-framed scoreboard: **Legit**, **Hmm…** or **Sus!**

Before every reveal, the rest of the room calls it: each friend taps *Legit* or *Sus* next to
their name. At the end, the show hands out awards: **Best poker face**, **Most sus**, **Biggest
spike**, and **Best lie detector**, for the friend whose calls matched the meter most often.

- **Party mode:** 2–8 players take turns in the hot seat and ask each other questions. Nothing to
  ask? *Suggest one* puts a card from the Mild or Spicy deck on screen for the asker to read out.
- **Solo mode:** the host reads the questions, and they get hotter as the turn goes on.
- 1, 3 or 5 questions each. The lobby tells you how long the game will take before you start.

It reads **stress, not truth**. The game says so in the lobby, in How to play and in the score
guide, because a racing heart means nervous, not guilty.

## Demo

{% embed https://youtu.be/z5P7-8B8kL4 %}

The video shows the live SmartSpectra signals in a real game:

- **Calibration:** live BPM and SmartSpectra's pulse waveform while the player sits still, then
  warm-up questions answered out loud.
- **A question:** the live transcript, the pulse card's trend line moving against the player's
  normal, the blink count, and an expression #tag stamped on the camera.
- **The verdict:** pulse, blink and pause tiles, and a chart of the pulse through the question.
- **Bad light:** the lights go down, "Too dark" is stamped on the camera and the reading pauses;
  the lights come back and it picks up.
- **The Proof Panel:** the raw SmartSpectra values behind every score.

## Code

**[github.com/littlepaprikalab/susometer](https://github.com/littlepaprikalab/susometer)**

To run it (full steps in the README):

1. You need a Mac with **Xcode 26+**, an **iPhone on iOS 17+** (the simulator has no camera) and
   **Flutter 3.38+**.
2. `flutter pub get`, open `ios/Runner.xcworkspace`, choose your signing team, then
   `flutter run --release`.
3. Get a free API key at [physiology.presagetech.com](https://physiology.presagetech.com). In the
   app, tap the gear, paste the key and tap **Save & test**.

There's no account or login. The only credential is your own Presage key.

Stack: Flutter for the UI, and a thin Swift bridge around the **SmartSpectra Swift SDK 3.4.0**.
`flutter test` runs about 600 tests without a phone.

**For judges:** long-press the lobby logo to turn on the **Proof Panel**, which overlays the raw
SmartSpectra stream on every measuring screen.

## How It Responds to Human Signals

### The signals

All live, from the SmartSpectra Swift SDK:

| Signal | What the game does with it |
|---|---|
| **Pulse rate** + confidence | Live BPM card with a trend line against your normal. 45% of the score. |
| **Pulse waveform** (arterial pressure trace) | Drawn live during calibration. The app also finds individual heartbeats in it (below). |
| **Blinking** | Live blink count. A burst of blinks, or a long "freeze", is 25% of the score. |
| **Expressions** | Your strongest expression is stamped on the camera as a #tag (#surprise, #happy…). Surprise, fear, contempt and disgust are 15% of the score. |
| **Talking** | Tells the asker's voice apart from the player's, and times the pause before answering (15%). |
| **Validation status** | "Too dark", "Hold still", "Move closer" are stamped on the camera. Bad stretches never get scored. |
| **HRV** (RMSSD) | Shown in the Proof Panel, not scored. |

### What happens in a turn

**1. Calibration learns your normal.** You sit still until the camera has your pulse (8 to 20
seconds), then answer three easy warm-ups out loud as the host reads them ("Cats or dogs? Tell me
why"). That sets your resting pulse, how often you blink while chatting, how strong your
expressions get, and how fast you usually start answering. It locks in only after 12 s of
confident pulse with your face in frame 80% of the time.

**2. Every question is scored against that normal.** Each of the four parts counts only what's
beyond your own normal wobble:

- **Pulse (45%):** how far your heart rate rose compared with your warm-ups and earlier answers.
- **Blinks (25%):** blinks beyond what chance would explain at your rate, or a freeze longer than
  chance would explain.
- **Expressions (15%):** how far surprise, fear, contempt or disgust went above your warm-up peak.
- **Hesitation (15%):** extra time to start answering, beyond your usual. The first extra second
  is free, since real questions take more thought than warm-ups.

Then `score = 100 × (weighted sum)^0.8`: **Legit** under 35, **Hmm…** 35–59, **Sus!** 60+. So a
calm, honest answer scores near 0. I checked that by simulation: thousands of made-up players
answering through the real scoring code. About 85% of ordinary honest answers come out Legit and
none Sus, while a clear stress reaction comes out Sus about 87% of the time.

**3. You see it react live.** While the player answers, the pulse card's trend line climbs or
settles against a dashed line at their normal, the blink count ticks, and the #tag stamp changes
within about a second of a big surprised face.

**4. The verdict shows its working.** Pulse, blink and pause tiles against the player's normal,
and a chart of the pulse through the question, scaled in BPM from their normal, with the answer
shaded. The **?** in the lobby
explains the whole score in plain words.

### Finding heartbeats in the waveform

SmartSpectra's pulse rate is a 12-second average, so a three-second spike arrives smeared and
late. The app also takes the SDK's **pulse waveform** and finds each heartbeat itself: it
band-pass filters the waveform, picks the peaks, and throws out missed or extra beats. From the
beat-by-beat rate it reads how far the pulse rose, how high it ran, and the brief slowdown after a
pointed question that concealed-information research reports most often.

It only trusts the beats when they agree with the SDK's own pulse within 8 BPM and cover 60% of
the question. Otherwise the score uses the SDK's pulse, and the Proof Panel says which one it
used and why.

### Never a fake verdict

- Pulse samples under 40% confidence are ignored, and so are samples more than 2 s into a
  validation problem.
- If less than 60% of a question is clean, the show says **No clean read** with the real reason
  ("The camera lost Sam's face for about 5 seconds") and offers *Ask it again*.
- After the camera restarts, a question waits ("Finding the pulse…") instead of starting blind.
- If the camera preview freezes, a watchdog restarts it within about 5 seconds.

### Turn-taking with the talking flag

There's no speaker diarization. SmartSpectra's **talking** flag says when the hot-seat player is
speaking, so speech heard while they're quiet is the question, and speech while they talk is the
answer. A party is too noisy for silence detection, so only taps move the game on (*Done asking*,
*Final answer*, *Reveal*). The timing still comes from the voice and the camera: the pause is
counted from the asker's last word, so a slow tap doesn't make anyone look hesitant.

### How I integrated the SDK

- **Swift bridge.** `SmartSpectraSDK` is `@Observable` and `@MainActor`, so the bridge watches it
  with `withObservationTracking`, re-armed after every change. It dedupes samples by timestamp,
  turns blink and talking frames into events, and streams snapshots at about 10 Hz to Flutter over
  an `EventChannel`, with the waveform's own SDK timestamps so beats line up with everything else.
- **Camera preview.** `sdk.imageOutput` is shown in a native `UIView`, embedded in Flutter as a
  platform view. The SDK hands every camera frame to the main thread, the same thread Flutter runs
  Dart on, so the measuring screens redraw about 10 times a second instead of on every display
  frame, to keep the preview from falling behind.
- **Voice.** Speech recognition is `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`.
  The host is `AVSpeechSynthesizer`, and the mic is muted while the host talks so the transcript
  never contains the host.
- **Game logic** (scoring, turn-taking, the state machine) is plain Dart. It's tested with
  synthetic SmartSpectra streams, fuzzed with random taps and failures, and played through whole
  simulated parties of made-up people.

## Prize Categories

**Most Creative or Delightful Use**

Every friend group has someone who swears they can always tell when you're lying. Sus-o-meter
gives them a scoreboard, and then checks their work. The meter judges the room as much as the
player: **Best lie detector** goes to whoever's gut matched the pulse most often.

What makes it playful:

- **It's a show, not a dashboard.** A 70s game-show set: a bulb-framed scoreboard, an applause
  meter, a drumroll and a 3-2-1 countdown before every verdict, a buzzer for Sus!, and a host who
  calls on people by name. Every sound effect was synthesized for the game.
- **The biometrics are the punchline.** The #tag stamp lands on your face mid-answer
  (#surprise!), and the verdict's pulse chart shows where your heart rate climbed.
- **Everyone plays at once.** One person is measured, but the whole room asks, votes and argues.

What makes it unexpected is the restraint. It never claims to catch a liar. It compares you only
with yourself, so a naturally fast heart doesn't make you guilty, and it would rather say "No
clean read" than make up a verdict.

## Consent and Data Handling

**Consent, per player, per game.** Before anyone is measured, the phone is passed to them and a
screen says "Only Sam can say yes. Everyone else, hands off." It lists what the front camera reads
(pulse, blinks, facial expressions, when you start talking) and what happens to it. The player
taps **I agree, measure me** or **Skip my turn**. iOS also asks for camera permission. The camera
only runs during that player's turn, and they watch their own face in the live preview while
they're measured, so nobody is measured without knowing it.

**What stays on the phone:**

- **Video** is processed on the phone by the SmartSpectra SDK. It's never saved or sent.
- **Audio** goes only to Apple's on-device speech recognition. It's never recorded. If on-device
  recognition isn't available, the app does **not** fall back to Apple's servers; it plays on
  without transcripts. The lobby tells everyone at the table that voices are turned into text on
  the phone.
- **Scores, pulse readings and transcripts** live only in memory. There are no accounts, no
  analytics and no backend, and game data is never written to disk.

**What leaves the phone:**

- **Presage sign-in:** the SDK sends your API key to Presage to start a session.
- **LLM Insights (from the SDK, can't be turned off):** SmartSpectra 3.4.0 automatically sends
  "vitals check-ins" once the pulse is stable (about 15 seconds in), again once HRV is, and every
  60 seconds after that: buffered **pulse rate and HRV values** (never video or face images), a
  fixed prompt and a session ID go to Presage,
  which asks an LLM for a summary. The SDK has no setting to stop this. The app never asks for an
  insight and never shows one. The consent screen tells each player: "Your pulse numbers (not
  video) go to Presage for an AI check-in."
- **SDK telemetry:** **off by default** (the SDK's own default is on). You can opt in under
  Settings, and the consent screen shows whether it's on. Presage then gets an anonymous
  per-session diagnostic summary with no video, no vitals and no identifiers
  ([Presage's telemetry docs](https://smartspectra.presagetech.com/docs/telemetry-and-privacy)).
- **Share results:** only if you tap it, through the iOS share sheet. The image has names, scores
  and awards only, never questions or answers.

**Retention and deletion:**

- Results (scores, pulse charts, transcripts) stay in memory for the Leaderboard and Replay until
  **Play again**, **Wipe everything**, Settings → **Wipe all game data now**, or the app closes.
- The **Presage API key** is stored in the iOS Keychain on this device only. **Remove** in
  Settings deletes it. iOS can keep Keychain items after an app is deleted, so on its first
  launch after a fresh install the app wipes any key left over.
- The only other thing written to the phone is one flag that tells the app it's a fresh install.

**What it isn't.** Not a lie detector, not a medical device. No diagnosis, no health advice, no
treatment claims. It measures stress reactions for fun, only from a player who said yes.

## Agent Session

Sus-o-meter was designed and built with Claude Code: the spec, the Swift bridge, the scoring, the
tests and the simulated parties.

[AGENT SESSION EMBED]

<!-- Upload at https://dev.to/agent_sessions/new, slice the parts worth showing, paste the embed
here, and click Make Public. Check the transcript for keys first. -->
