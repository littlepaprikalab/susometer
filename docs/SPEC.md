# Sus-o-meter — Design & Build Spec

> Lives at `docs/SPEC.md`. It's the design reference for this repo: what the app does, how scoring and turn detection work, and how data is handled. It was written before implementation, so where the code and this doc differ, the code wins. Update this doc when you change a decision.

> A camera-and-voice party game for iPhone. One player sits in the "hot seat", friends ask questions out loud, and the app reads the player's live pulse, blinks, expressions and hesitation with the **Presage SmartSpectra SDK**, then delivers a game-show verdict: **Legit / Hmm… / Sus!**
>
> **It reads stress, not truth.** This is an entertainment game, never a lie detector. Say so in the app, the README and the DEV post.

- **Hackathon:** DEV Presage Challenge, tag `#presagechallenge`. Solo entry, entrant is 18+.
- **Visual mockup (source of truth for look and layout):** exported screens in `docs/design/`. Screen names below match the file names and artboard titles there.
- **Target:** iPhone only, iOS 17+, portrait, built with **Flutter (UI) + native Swift (SmartSpectra bridge)**.

---

## 0. Challenge requirements (non-negotiable)

Every item must be visibly satisfied in the repo and the demo video:

1. SmartSpectra SDK integrated into a working app, using **live** Presage signals. We use: pulse rate, HRV (session summary only), blinking, talking, expressions, plus validation status and confidence.
2. A public GitHub repo with **setup instructions** (README).
3. A **demo video** showing the live signals in action. Use the Proof Panel (§10).
4. A **DEV post** using the challenge's submission template, tagged `#presagechallenge`, with a complete **Consent and Data Handling** section (§8). Disclose storage, sharing, retention, deletion, SDK telemetry and any optional AI or cloud service use.

---

## 1. Tech stack

| Concern | Choice | Notes |
|---|---|---|
| UI | Flutter (stable), Dart 3 | iOS target only. |
| State | `flutter_riverpod` (or plain `ChangeNotifier` if simpler) | One `GameController` owns the state machine (§4). |
| Vitals | **SmartSpectra Swift SDK** (Swift Package, v3.4.x at time of writing), iOS 17+ | No Flutter plugin exists, so write a thin Swift bridge (§6). |
| Camera preview | Native `UIView`, shown in Flutter via `UiKitView` (platform view) | It displays `sdk.imageOutput` with `sdk.config.imageOutputEnabled = true`. |
| Speech-to-text | Apple Speech, **on-device only** | Either the Flutter `speech_to_text` plugin with on-device mode, or a small native `SFSpeechRecognizer` in the bridge with `requiresOnDeviceRecognition = true`. Prefer native if the plugin fights the SDK for the audio session. |
| Host voice | iOS text-to-speech (`AVSpeechSynthesizer`), via `flutter_tts` or native | |
| Sound effects | `audioplayers` or `just_audio` | Bundle CC0 sound files under `assets/sfx/` and credit them in the README. |
| Haptics | Flutter `HapticFeedback` (built in) | |
| Fonts | Google Fonts **Bowlby One SC** (display) and **Work Sans** (500/600/700) | Bundle the font files. Don't fetch at runtime. |

Verify every package name and version on pub.dev before adding it. The choices above are suggestions, not requirements.

---

## 2. Screens (match the mockup)

**Main flow:** `1 Lobby` → `2 Hot-seat consent` → `3 Calibrate baseline` → `4a Host: ask your question` (or `4a Solo: the host asks`) → `4b Sam answers · Final answer` → *Call it!* (room vote, §5.6) → *Countdown* → `5 Verdict` → (next question, back to 4a) … → (end of turn: next player goes to 2) … → `6 Leaderboard` → `7 Replay`.

**Edge screens:** `E1 How to play` (shown once, before the first turn), `E2 Camera/mic permission off`, `E3 Bad signal mid-question` (a banner over 4a/4b), `E4 No clean read: redo`, `E5 SDK sign-in failed / offline`, `E6 End the show early` (bottom-sheet confirmation, reachable from Pause).

**Settings:** `8 Settings · Presage API key`, opened from the gear button at the top right of the Lobby.

Two screens are **not mocked**, so build them in the same style:
- **Countdown:** full screen, mustard background, flashing marquee bulbs, a giant "3… 2… 1…" in Bowlby, plus a drumroll.
- **Call it!:** the room vote, see §5.6.

### Screen notes
- **1 Lobby:** players list (2–8), add/remove, a **Party / Solo · host asks** switch, questions per turn (3 / 5 / 7, default 5), a deck choice (Mild / Spicy, default Mild), and "Start the show". The line "For fun only. Measures stress reactions, not truth." is always visible.
- **2 Consent:** "Pass the phone to {name}". It lists what the camera reads and what happens to the data, then "I agree, measure me" or "Skip my turn". **Consent is collected per player, per game, from the person being measured.** In the lobby, a one-line note says that voices are transcribed on-device for everyone at the table.
- **3 Calibrate:** two-part progress: **Sit still** (about 20 s quiet), then **Chat a bit** (2–3 warm-ups read by the host, answered out loud). Face and light chips, live BPM and waveform, a "Doesn't apply? Next one" button. It auto-advances once the baseline is valid (§5.2).
- **4a Party:** the host says "Ask your question!" The asker's speech is transcribed live. The camera is visible with "Measuring {name}" and live BPM. A hint reads "{name}: just start answering when you're ready." Backup button: "Too loud? Tap when done asking." Pause button.
- **4a Solo:** the host reads a question from the selected deck, shown on a tomato card. A "Different question" button skips it. Otherwise identical.
- **4b:** the question is pinned, the host says "{name}, your answer?", and the answer is transcribed live. A hesitation chip shows "Took X.Xs to start answering". Live pulse and blink cards. A huge **Final answer** button covers most of the bottom area. It auto-ends after 4 s of silence.
- **5 Verdict:** the question and answer text, a bulb-framed scoreboard (color by verdict), the 10-block applause meter, and three stat tiles (pulse change, blink change, hesitation). It shows how each room vote went, then "End turn" and "Next question".
- **6 Leaderboard:** Best poker face (lowest average), Most sus (highest average), **Best lie detector** (§5.6), Biggest spike (highest single score, with its question), a ranked list, "Play again", "Watch the replay", "Share results".
- **7 Replay:** player tabs. One card per question: Q, A, pulse sparkline, score badge. "Wipe everything" and "Play again".
- **8 Settings:**
  - **Presage API key card:** a password-style field with Show, Paste, Remove and **Test connection** buttons, plus a status chip with three states: *Connected* (teal), *No key yet* (tomato), *Key rejected* (tomato, shows the SDK error code). Helper text says the key is saved in the iPhone's Keychain, used only to sign in to Presage, and links to physiology.presagetech.com.
  - **Toggles:** Host voice (on), Sound effects (on), Haptics (on, "never while measuring"), SDK telemetry (**off by default**), Proof panel (off).
  - **"Wipe all game data now"** button, and a footer: "For fun only. Not a medical device. Not a lie detector."
  - **First run / no key:** "Start the show" in the Lobby opens Settings with the key field focused and the *No key yet* chip, instead of starting. E5 (sign-in failed) links back here.

---

## 3. Design tokens (from the Style B "70s game show" mockup)

```
Colors
  mustard  #F2B33D   app background
  ink      #2A160C   text, borders, shadows, dark pills
  cream    #FFF4DF   cards, light buttons
  tomato   #D9412B   "Sus", pulse color, alerts (use for graphics or text ≥ 24px only)
  teal     #1F6F78   "Legit", primary action buttons (cream text on teal)
  brown    #8A4B1C   "Hmm…" verdict board
  bulb     #FFE9A8   marquee bulbs, face-guide oval
  unlit    #E8D9BC   empty meter blocks
  meter ramp (10 blocks, low→high):
    #1F6F78 #1F6F78 #3E8C7A #8FAE5B #E7C64A #FFE9A8 #F08A4B #E5683A #D9412B #B8301D

Type
  Display: Bowlby One SC   (titles 26–40, scoreboard number 96, verdict word 38)
  Body:    Work Sans 500/600/700  (body 15–17, labels 12–14)

Shape
  Card: cream fill, 3px ink border, radius 18–20
  Chunky button: 3px ink border, radius 16, hard drop shadow 0 5px 0 ink, height 58–60
  Pill: ink fill, mustard text, radius 20
  Camera window: ink fill, 3px ink border, radius 24, dashed bulb-colored face oval
```

Accessibility: touch targets ≥ 44 pt. Never put small text in tomato. Icons are stroke SVG or SF Symbols, never emoji. Transcripts double as captions for the host's voice.

---

## 4. Game state machine

```
Lobby
 └─ start → [first game? HowToPlay] → for each player in order:
     Consent ──skip──▶ next player
       └─ agree → Calibrate(quiet 20s → warm-ups x2–3) ──invalid──▶ stay / show E3 hints
            └─ baseline valid → for q in 1..N:
                 Ask (party: listen to asker | solo: host reads deck question)
                   └─ question end detected (§7) → Answer
                        └─ Final answer tap | 4s silence → Settle (until ≥12s since question end)
                             └─ window valid? ──no──▶ E4 Redo / Skip
                                  └─ yes → CallIt (room vote; skipped in solo) → Countdown → Verdict
                 end of questions or "End turn" → next player
 └─ all players done | E6 confirmed → Leaderboard → Replay → Wipe → Lobby
Pause (from 4a/4b): Resume · Skip question · End the show (E6)
```

The SmartSpectra session runs continuously from Calibrate until the end of that player's turn. Stop it between players. Call `reset()` before each new player's calibration.

---

## 5. Measurement and scoring

### 5.1 Requested metrics
```swift
sdk.config.requestedMetrics = SmartSpectraConfig.breathingMetrics + [
  .pulseRate, .hrv, .blinking, .talking, .expressions
]
```
Breathing is collected but **not scored**, because talking hurts breathing accuracy. Face landmarks are optional and not needed.

### 5.2 Baseline (per player, per game)
- **Quiet phase (about 20 s):** collect pulse samples that pass the confidence check, and the blink rate.
- **Chat phase (2–3 warm-ups):** collect the same, plus the expression probability mean, the talking blink rate and the answer latency for each warm-up.
- **Baseline is valid** when it has ≥ 12 s of confident pulse samples **and** the face is present ≥ 80% of the time. Otherwise, keep calibrating and show E3 hints.
- Store: `basePulse` (median), `baseBlinkRate` (blinks/min), `baseExpr[category]` (mean), `baseLatency` (median warm-up latency, default 1.0 s).

### 5.3 Question window
- `tQ0` = question starts (asker begins speaking, or the host starts reading in solo).
- `tQ1` = question ends.
- `tA0` = the player starts talking.
- `tA1` = Final answer, or silence timeout.
- Measurement window = `[tQ0, max(tA1, tQ1 + 12s)]`. The **Settle** phase holds the countdown until the window closes.
- **Hesitation** = `tA0 − tQ1`, in seconds.

### 5.4 Score (0–100, entertainment-grade)
Normalize each feature against the player's baseline, then clamp to 0–1:
- `zPulse = clamp((mean(confident pulse in window) − basePulse) / 15 BPM)`
- `zBlink = clamp(((blinkRate − baseBlinkRate) / max(baseBlinkRate, 6)) / 0.6)`. A blink "freeze" (no blinks for ≥ 6 s when the baseline is ≥ 12/min) also counts as 0.6.
- `zExpr  = clamp(max over window of (p[surprise|fear|…] − baseExpr) / 0.4)`. Check the category names in the SDK's Data Types reference.
- `zHes   = clamp((hesitation − baseLatency) / 3.0)`

`raw = 0.45·zPulse + 0.25·zBlink + 0.15·zExpr + 0.15·zHes`
`score = round(100 · raw^0.8)`

Keep every weight and constant in one `ScoringConfig` so it can be tuned after play-testing.

**Verdict:** `< 35` Legit (teal board), `35–59` Hmm… (brown), `≥ 60` Sus! (tomato).

### 5.5 Confidence gating (never fake a verdict)
- Ignore samples whose confidence is below threshold, or that arrive while `validationStatus` is not OK. Find the confidence field name on `MeasurementWithConfidence` in the API reference; it isn't documented on the metrics page.
- If less than 60% of the window has confident pulse and a present face, the result is **No clean read** (E4: "Ask it again" / "Skip it"). Show the reasons using the actual validation hints seen.
- Rate metrics can be `nil` between updates. Keep the last valid value and use sample timestamps. Reset retained values at session start and stop.

### 5.6 Room vote and "Best lie detector"
- **Votes happen before the reveal** (the *Call it!* screen, after Settle, before Countdown), so voters can't copy the meter. This is a change from the mockup, where the vote sits on the Verdict screen.
- *Call it!* shows one chip per non-hot-seat player. The hot-seat player holds the phone out, and each voter taps their own chip to cycle **Legit / Sus** (unset means abstain). A "Reveal" button, or a 10 s auto-timeout, moves on. Measurement is already finished, so movement here is fine.
- A vote **matches** if it's Sus and the verdict is Sus, or Legit and the verdict is Legit. Hmm… verdicts don't count either way.
- **Best lie detector** = the most matches; ties go to the higher match rate. It's shown as "Matched the meter X of Y".
- Solo mode has no voting and no Best lie detector award.

---

## 6. Swift ⇄ Flutter bridge

`ios/Runner/Presage/` contains `PresageBridge.swift` and `CameraPreviewView.swift` (the platform view).

**MethodChannel `sus/presage`**
- `configure({ telemetry: bool })`: reads the API key from the Keychain (§9), sets `sdk.config.apiKey`, `requestedMetrics`, telemetry, `imageOutputEnabled = true`, and `useCamera(.default)` (front camera). Keep all Presage auth setup in this one function, so switching to Presage OAuth later only touches this function and Info.plist.
- `setApiKey(String)`, `hasApiKey() → bool`, `clearApiKey()`: Keychain read/write lives in Swift (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). **The key never comes back to Dart.** Dart only ever sends it once, on save. `apiKeyHint() → "••••1a2b"` returns only the last 4 characters, for display after saving. The Show button only reveals text the user is still typing, before they save.
- `testConnection() → { ok, code, message }`: configures, starts a session briefly, then stops. It succeeds if the status reaches running without an auth error. Find out on the device whether auth happens at `start()` without frames; if it doesn't, run a 2–3 s camera session.
- `start()`, `stop()`, `reset()`: async. Errors return a `PlatformException` with the SDK error `code` and `message`.

**EventChannel `sus/presage/stream`** (about 10 Hz, throttled), JSON maps:
```json
{ "t": 1730851200123,                      // ms
  "pulse": 84.0, "pulseConf": 0.82,        // last valid
  "rmssd": 41.2, "hrvConf": 0.0,           // 0 until 60s window fills
  "blink": false, "talking": true,
  "expr": { "surprise": 0.42, "...": 0.0 },
  "validation": { "code": "OK|FACE_TOO_FAR|FACE_TOO_CLOSE|TOO_DARK|TOO_BRIGHT|EXCESSIVE_MOTION|FRAME_RATE_TOO_LOW", "hint": "..." },
  "status": "idle|starting|running|stopping|error",
  "error": null }
```
Blink and talking events should also be sent as edges (`blinkEvent`, `talkStart`, `talkEnd`) so Dart can count them precisely.

**Observation:** `SmartSpectraSDK.shared` is `@Observable`. Outside SwiftUI, use `withObservationTracking` and re-arm after each change, as the docs describe. Push to the EventChannel on the main thread.

**Camera preview:** a `UiKitView` hosting a native view that renders `sdk.imageOutput`. Mirror it for the front camera.

**Fallback if the camera and mic conflict:** switch to `useCustomInput(frameTransform: .none)` and run your own `AVCaptureSession` with both video and audio. Send `CMSampleBuffer`s with `input.sendFrame(sampleBuffer)` from a serial queue. Timestamps must be strictly increasing, and a gap over 2 s triggers `.timestampGap`, after which you stop and restart.

Verify all API names against https://smartspectra.presagetech.com/docs/swift/ (headless mode, metrics, API reference). The Presage MCP server can also fetch the API key.

---

## 7. Voice flow and turn detection

**Roles.** The *host* is the app's text-to-speech voice: it runs the show, reads warm-ups (and questions in solo mode), counts down and announces verdicts. The *asker* is a human (party mode). The *player* is the person in the hot seat.

**Half-duplex rule.** Pause speech recognition while the host speaks or any sound effect plays. Resume about 150 ms after playback ends. The transcript must never contain the host.

**Speaker separation without diarization.** Use SmartSpectra `talking` for the player:
- mic speech while the player is **not** talking = the asker
- mic speech while the player **is** talking = the answer

**Question end (`tQ1`):** the first of:
1. the player starts talking (`talkStart`), or
2. 1.5 s of silence after asker speech. The host then says "{name}, your answer?", or
3. the backup button "Too loud? Tap when done asking".

**Answer end (`tA1`):** the **Final answer** tap (primary), or 4 s of silence after the player last talked.

**No-mic mode** (mic or speech permission denied, E2 "Play without voice"): no transcripts. The host still speaks. Use tap-to-advance: "Done asking" → answer → "Final answer". Hesitation is measured from the "Done asking" tap to `talkStart`.

**Transcripts:** use partial results for live display. Keep the final text per phase, in memory only.

---

## 8. Data handling and privacy (also the DEV post's Consent section)

| Data | Where | Retention | Shared? |
|---|---|---|---|
| Camera video | Processed on-device by SmartSpectra | Never stored | Never |
| Vitals and face signals | In-memory game state | Until the game ends or "Wipe everything" | Never |
| Audio | On-device Apple speech recognition (`requiresOnDeviceRecognition = true`) | Never stored | Never |
| Transcripts (Q and A text) | In memory | Until Wipe or the app closes | Never. **Excluded from the share card.** |
| Names and scores | In memory | Until Wipe or the app closes | Only if the user taps Share (an image with names, scores and awards) |
| SmartSpectra telemetry | SDK | n/a | **Off by default** (`enableTelemetry = false`). The user can opt in from Settings. When on, the SDK sends an aggregate per-session diagnostic summary: no video, no vitals values, no identifiers. |
| Presage API key | iOS Keychain, this device only | Until "Remove" in Settings or the app is deleted | Sent only to Presage to start a session |
| SmartSpectra auth | SDK contacts Presage to start a session with the API key | n/a | Required by the SDK |
| AI/LLM services | **None used.** SmartSpectra LLM Insights is not enabled. | — | — |

- No accounts, no analytics, no backend, no disk persistence. Don't write game data to `SharedPreferences` or files.
- Consent: per-player opt-in on screen 2. Skip is always available. The lobby notes that voices are transcribed on-device.
- In the app and in the post, state plainly: wellness and entertainment only, not medical, not a lie detector.
- **Test before claiming:** whether a game can start offline (E5 covers failure), and that no network traffic happens besides SDK auth (check with Wi-Fi off, or a proxy).

---

## 9. Config, secrets, permissions

- **.gitignore (set up before the first commit):**
  ```
  ios/Flutter/Secrets.xcconfig
  ```
- **API key: entered at runtime in Settings, stored in the Keychain.** No key is ever compiled into the app or committed to the repo, so anyone cloning the public repo just pastes their own key on first launch.
  - Optional developer convenience (**debug builds only**): if a gitignored `ios/Flutter/Secrets.xcconfig` defines `PRESAGE_API_KEY`, it's exposed through Info.plist as `PresageApiKey = $(PRESAGE_API_KEY)`. On first debug launch, if the Keychain is empty, it's copied into the Keychain once. Release builds ignore it. Commit a `Secrets.example.xcconfig` showing the format.
  - The README explains how to get a key from the Presage developer portal and where to paste it.
  - For production, switch to Presage's OAuth (App Attest) option. Then no key is involved at all, and only `configure()` and Info.plist change.
- **Info.plist usage strings:**
  - `NSCameraUsageDescription`: "Sus-o-meter reads pulse, blinks and expressions from your face. Video stays on this phone."
  - `NSMicrophoneUsageDescription`: "Lets the host hear questions and answers. Audio stays on this phone."
  - `NSSpeechRecognitionUsageDescription`: "Turns speech into on-screen text, on this phone."
- Lock the app to portrait. Keep the screen awake during a game (`wakelock_plus` or `UIApplication.isIdleTimerDisabled`).
- **Thermal:** watch `ProcessInfo.thermalState`. At `.serious`, show a "Give the phone a breather" note between turns.

---

## 10. Proof Panel (for judges and the demo video)

Turn it on in Settings ("Proof panel"), or with the shortcut below.


Long-press the logo (or tap it 5 times) to toggle a translucent overlay on every measuring screen. It shows the raw stream: pulse and confidence, RMSSD and confidence, blink and talking flags, the top expression, the validation code and hint, the SDK status, and the timing markers `tQ0`, `tQ1`, `tA0`, `tA1`. Record the demo with it on for part of the video.

---

## 11. Content: question decks (`assets/decks/*.json`)

- **warmup.json (about 30):** neutral and easy for anyone to answer: "What did you have for breakfast?", "What's the weather like today?", "Name something you can see that's blue."
- **mild.json (about 40):** "Have you ever re-gifted a present?", "Do you floss every day?", "Have you ever pretended to like a gift?"
- **spicy.json (about 40):** **PG-13.** Awkward and funny, never sexual, cruel, or about health, relationships, money, crime or real third parties. "Have you ever read someone's texts?", "Do you actually like your boss?"

Shuffle without repeats within a game. Party mode uses the decks only for warm-ups. Solo mode uses the selected deck for the main questions.

---

## 12. Sound and haptics

| Moment | Sound | Haptic |
|---|---|---|
| Turn starts | Short jingle (ends before listening) | — |
| Host lines | TTS | — |
| Countdown 3-2-1 | Drumroll | Light tap per number |
| Legit | Ding-ding | Double soft tap |
| Hmm… | Wah-wah | Single medium |
| Sus! | Buzzer | Heavy |
| Award reveal | Applause | Rumble |

**No haptics while measuring** (from Calibrate start until the window closes): vibration shakes a hand-held camera. Host voice, sound effects and haptics each have a toggle in Settings. Pause also has a quick mute.

---

## 13. Suggested project layout

```
lib/
  main.dart
  theme/ (tokens.dart, widgets: ChunkyButton, Card, Marquee, ApplauseMeter, HostBubble, MicLevel)
  game/  (game_controller.dart, state.dart, scoring.dart, scoring_config.dart, decks.dart)
  presage/ (presage_channel.dart, presage_models.dart, camera_preview.dart)
  voice/ (speech_service.dart, host_tts.dart, turn_detector.dart)
  screens/ (lobby, consent, calibrate, ask, answer, call_it, countdown, verdict, leaderboard, replay, edge/*)
  debug/ proof_panel.dart
ios/Runner/Presage/ (PresageBridge.swift, CameraPreviewView.swift)
assets/ (decks/, sfx/, fonts/)
test/ (scoring_test.dart, turn_detector_test.dart, game_controller_test.dart)
```
Add unit tests for scoring and turn detection with synthetic streams. They're runnable without a device.

---

## 14. Build milestones (each one leaves a submittable app)

0. **Repo setup:** `git init`, add the `.gitignore` from §9, and confirm `Secrets.xcconfig` is ignored (`git check-ignore -v ios/Flutter/Secrets.xcconfig`) **before** the first commit. Never commit the real API key.
1. **Bridge spike (riskiest, do first):** build a minimal Settings screen first (paste key, saved to the Keychain, Test connection), so a key is available without editing files. Then the Swift bridge streams live pulse, blink, talking and validation into a bare Flutter screen, with the camera preview. Then add speech recognition at the same time and confirm camera and mic coexist. If they don't, switch to custom input (§6). ✅ Accept when live BPM and the transcript both update together on the device.
2. **Core game:** lobby, consent, calibrate, tap-to-advance questions, scoring, verdict, leaderboard, Proof Panel, edge screens E2–E6.
3. **Voice host:** TTS prompts, solo mode, half-duplex rule.
4. **Turn detection:** auto question-end and answer-end (§7), backup buttons.
5. **Transcripts and Replay**, Call it! and Best lie detector, sounds and haptics, polish.
6. **Ship:** README (setup, API key, permissions, privacy, sound credits, limitations), demo video, DEV post.

---

## 15. Submission deliverables

**README:** what it is; the disclaimer; requirements (Mac with Xcode, iPhone on iOS 17+, Flutter, a Presage API key); setup steps (`flutter pub get`, `flutter run` on a device, then paste your Presage key in Settings on first launch; the optional `Secrets.xcconfig` is only for debug builds); architecture diagram (Flutter ⇄ MethodChannel/EventChannel ⇄ SmartSpectra); privacy table (§8); the scoring explanation; known limitations (lighting, motion, noise, not medical); credits.

**Demo video (about 2–3 min) shot list:** hook (a verdict buzzer moment) → lobby and consent → calibration with the live waveform → a party question with live transcripts → Final answer → Call it! → countdown → verdict → solo mode clip → E3 "too dark" recovery → Proof Panel showing raw SDK values → leaderboard and replay → "Wipe everything".

**DEV post outline:** follow the challenge's submission template. Sections: what I built; demo; how it uses SmartSpectra (which signals and why); how it works (architecture, scoring, turn detection with talking detection); **Consent and Data Handling** (the §8 table, in prose); limitations and ethics ("stress, not truth"); repo link; tag `#presagechallenge`.

---

## 16. Open items to verify on the device

- [ ] The camera (SmartSpectra) and mic (speech recognition) run together without audio session errors.
- [x] The confidence field name on `MeasurementWithConfidence`, and the expression category names (Data Types reference). *`confidence`, a percentage 0–100; expressions: angry, contempt, disgust, fear, happy, neutral, sad, surprise. See Decisions.*
- [ ] Whether the SDK needs network access to start, and its behavior offline.
- [ ] Whether `speech_to_text` on-device mode really avoids server recognition; if unsure, use native `SFSpeechRecognizer`.
- [ ] How best to implement **Test connection**: does auth happen at `start()` with no frames?
- [ ] How a handheld phone affects `EXCESSIVE_MOTION` frequency; adjust the copy that says "hold with both hands".
- [ ] Tune the `ScoringConfig` constants after 3–4 play-test games.

---

## Decisions made during build

Choices made once the real APIs were in hand. Where these differ from the sections above, these win.

### Milestone 0–1

1. **SmartSpectra SDK version and packaging.** SmartSpectra-Swift **3.4.0** (latest stable tag), added to the Runner target as a Swift Package with an exact-version pin. Flutter 3.47 uses Swift Package Manager by default, so there is no CocoaPods/Podfile. The SDK binary was built with Swift 6.2.4, so building needs **Xcode 26 or later**.
2. **Breathing metrics are not requested** (changes §5.1). Requested: `.pulseRate, .arterialPressureTrace, .hrv, .blinking, .talking, .expressions`. Breathing isn't scored anyway. More importantly, the SDK docs say LLM Insights auto-fire "once a session is running" and send buffered pulse/HRV/breathing values to Presage's LLM gateway, there is no documented switch to turn that off, and the docs say Insights need **breathing + cardio** active. Leaving breathing out removes that precondition. As a check, the bridge watches `sdk.insight` and reports `insightSeen` in the stream; the spike screen and Proof Panel show "LLM insight seen". It must stay "no" on the device before §8 can claim no vitals leave the phone.
3. **`.arterialPressureTrace` is requested** to draw the live pulse waveform on Calibrate (§2 "live BPM and waveform"). It's part of the SDK's cardio bundle and is never scored.
4. **SDK telemetry.** The SDK default is `enableTelemetry = true`. The bridge sets it to `false` when it registers at app launch, before any session can start, and `configure()` applies the Settings toggle (off by default).
5. **Confidence units.** The SDK reports confidence as a percentage (0–100) on `MeasurementWithConfidence.confidence`, `Hrv.confidence` and `ExpressionScore.confidence`. The bridge normalizes all of these to 0–1 (`pulseConf`, `hrvConf`, `expr`), so `ScoringConfig` thresholds are 0–1.
6. **Validation codes.** The SDK has more codes than §6 lists. All are sent as SCREAMING_SNAKE: `OK, NO_FACE_FOUND, MULTIPLE_FACES_FOUND, FACE_NOT_CENTERED, FACE_SIZE_OUT_OF_RANGE (deprecated), TOO_DARK, TOO_BRIGHT, CHEST_NOT_VISIBLE, CAMERA_TUNING, FRAME_RATE_TOO_LOW, EXCESSIVE_MOTION, FACE_TOO_CLOSE, FACE_TOO_FAR, FACE_TOO_HIGH, FACE_TOO_LOW, FACE_NOT_FORWARD`.
7. **Stream shape** (extends §6). One snapshot map every ~100 ms while a session is active. Edges come inside it as `events: [{e: blinkEvent|talkStart|talkEnd, t, ts}]` instead of separate messages. Extra keys: `pulseAt` (when the current pulse sample arrived; a new value means a fresh sample), `pulseStable`/`hrvStable` (SDK `stable` flags), `trace` (waveform samples since the last snapshot), `insightSeen`. Missing keys mean null.
8. **One time base.** `t` values are wall-clock milliseconds taken when the bridge observed the sample or edge, so they line up with speech-recognition timestamps for turn detection. Raw SDK timestamps (µs) ride along as `ts` for the Proof Panel.
9. **Speech recognition is native** (`SFSpeechRecognizer` in `ios/Runner/Voice/SpeechBridge.swift`), not the `speech_to_text` plugin, for full control of on-device mode and the audio session. Every request sets `requiresOnDeviceRecognition = true`. If on-device recognition isn't supported for the language, listening fails with `ON_DEVICE_UNAVAILABLE`; there is no server fallback. Audio session: `.playAndRecord`, mode `.default`, `.defaultToSpeaker`. Recognition runs in segments that restart after silence; Dart joins them (`TranscriptBuffer`). `pause()`/`resume()` implement the half-duplex gate for milestone 3.
10. **Settings live in memory only.** Toggles reset to their defaults on every launch (telemetry off), because nothing is written to disk (§8). Only the API key persists, in the Keychain.
11. **Keychain and app deletion.** iOS keeps Keychain items after an app is deleted, so the §8 claim "until the app is deleted" wouldn't hold on its own. On the first launch after an install, the app deletes any leftover key. It detects a fresh install with a single `UserDefaults` boolean (`sus.installMarker.v1`), which iOS does delete with the app. That flag is the only thing written outside the Keychain, and it holds no game data.
12. **Test connection** configures, starts a real SDK camera session, and passes when the pipeline reaches `running` and stays there for 2 s without a connection error (`authenticationFailed`, `creditExhausted`, `networkError`, `serverError`, `configurationFailed`). It needs camera permission. The result reports where auth was decided (`start` or `running`) and how long it took, to settle §16 on the device. Only auth-type codes show **Key rejected**; camera, network or timeout failures keep **Key saved** and show the reason.
13. **Keep-awake** uses `UIApplication.isIdleTimerDisabled` directly (a `setKeepAwake` call on the Presage channel) instead of a plugin.
14. **Portal link.** Until `url_launcher` is added, Settings offers "Copy portal link" for physiology.presagetech.com.
15. **Home screen during milestone 1** is a bare "Bridge spike" screen (camera preview, live signals, transcript). The Lobby replaces it in milestone 2.

