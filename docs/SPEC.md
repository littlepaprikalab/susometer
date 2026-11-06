# Sus-o-meter — Design & Build Spec

> Lives at `docs/SPEC.md`. It's the design reference for this repo: what the app does, how scoring and turn detection work, and how data is handled. It was written before implementation, so where the code and this doc differ, the code wins. Update this doc when you change a decision.

> A camera-and-voice party game for iPhone. One player sits in the "hot seat", friends ask questions out loud, and the app reads the player's live pulse, blinks, expressions and hesitation with the **Presage SmartSpectra SDK**, then delivers a game-show verdict: **Legit / Hmm… / Sus!**
>
> **It reads stress, not truth.** This is an entertainment game, never a lie detector. Say so in the app, the README and the DEV post.

- **Hackathon:** DEV Presage Challenge, tag `#presagechallenge`. Solo entry, entrant is 18+.
- **Visual mockup (source of truth for look and layout):** the Design canvas's screen sources in `docs/design/mocks/` (HTML, one file per artboard; `docs/design/README.md` maps files to screens). Screen names below match the artboard titles there.
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

**Edge screens:** `E1 How to play` (shown once, before the first turn), `E2 Camera/mic permission off`, `E3 Bad signal mid-question` (stamped on the camera on 4a/4b, decision 69; the mock's banner is gone), `E4 No clean read: redo`, `E5 SDK sign-in failed / offline`, `E6 End the show early` (bottom-sheet confirmation, reachable from Pause).

**Settings:** `8 Settings · Presage API key`, opened from the gear button at the top right of the Lobby.

Two screens are **not mocked**, so build them in the same style:
- **Countdown:** full screen, mustard background, flashing marquee bulbs, a giant "3… 2… 1…" in Bowlby, plus a drumroll.
- **Call it!:** the room vote, see §5.6.

### Screen notes
- **1 Lobby:** players list (2–8), add/remove, a **Party / Solo · host asks** switch, questions per turn (3 / 5 / 7, default 5), a deck choice (Mild / Spicy, default Mild), and "Start the show". The line "For fun only. Measures stress reactions, not truth." is always visible.
- **2 Consent:** "Pass the phone to {name}". It lists what the camera reads and what happens to the data, then "I agree, measure me" or "Skip my turn". **Consent is collected per player, per game, from the person being measured.** In the lobby, a one-line note says that voices are transcribed on-device for everyone at the table.
- **3 Calibrate:** two-part progress: **Sit still** (about 20 s quiet), then **Chat a bit** (2–3 warm-ups read by the host, answered out loud). Face and light chips, live BPM and waveform, a "Doesn't apply? Next one" button. It auto-advances once the baseline is valid (§5.2).
- **4a Party:** the host says "Ask your question!" The asker's speech is transcribed live. The camera is visible with "Measuring" and live BPM. A hint reads "{name}: just start answering when you're ready." Backup button: "Too loud? Tap when done asking." Pause button.
- **4a Solo:** the host reads a question from the selected deck, shown on a tomato card. A "Different question" button skips it. The card stays on screen after the host finishes, until the player starts answering or taps "Ready to answer" (see decision 58). Otherwise identical.
- **4b:** the question is pinned, the host says "{name}, your answer?", and the answer is transcribed live under "Hot seat · talking" (or "· listening"). A hesitation chip shows "Took X.Xs to start answering". Live pulse and blink cards. A huge **Final answer** button covers most of the bottom area. It auto-ends after 4 s of silence.
- **5 Verdict:** the question and answer text, a bulb-framed scoreboard (color by verdict), the 10-block applause meter, and three stat tiles (pulse change, blink change, hesitation). It shows how each room vote went, then "End turn" and "Next question".
- **6 Leaderboard:** Best poker face (lowest average), Most sus (highest average), **Best lie detector** (§5.6), Biggest spike (highest single score, with its question), a ranked list, "Play again", "Watch the replay", "Share results".
- **7 Replay:** player tabs (each with the player's initial), or just the player's name and question count when one contestant played. One card per question: Q, A, pulse sparkline (with the player's normal and the peak in BPM under it), score badge. "Wipe everything" and "Play again".
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
- Store: `basePulse` (median), `baseBlinkRate` (blinks/min while chatting, decision 65), `baseExprPeak[category]` (the warm-ups' peak, decision 65), `baseLatency` (median warm-up latency, default 1.0 s).

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
- `zBlink = clamp(((blinkRate − baseBlinkRate) / max(baseBlinkRate, 6)) / 0.6)`. A blink "freeze" (no blinks for ≥ 6 s when the baseline is ≥ 12/min) also counts as 0.6. *Replaced by a chance-aware version, decision 65.*
- `zExpr  = clamp(max over window of (p[surprise|fear|…] − baseExpr) / 0.4)`. Check the category names in the SDK's Data Types reference. *Now against the warm-up peak, smiles taken out, decision 65.*
- `zHes   = clamp((hesitation − baseLatency) / 3.0)`. *Now with 1 s free, decision 65.*

`raw = 0.45·zPulse + 0.25·zBlink + 0.15·zExpr + 0.15·zHes`
`score = round(100 · raw^0.8)`

Keep every weight and constant in one `ScoringConfig` so it can be tuned after play-testing.

When the pulse waveform gives good heartbeats, `zPulse` comes from the beat-by-beat shape ranked against the player's earlier answers instead (decision 63).

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
| Vitals and face signals | In-memory game state | Until the game ends or "Wipe everything" | Not by the app. The SDK sends pulse and HRV values to Presage's LLM Insights (below, decision 67) |
| Audio | On-device Apple speech recognition (`requiresOnDeviceRecognition = true`) | Never stored | Never |
| Transcripts (Q and A text) | In memory | Until Wipe or the app closes | Never. **Excluded from the share card.** |
| Names and scores | In memory | Until Wipe or the app closes | Only if the user taps Share (an image with names, scores and awards) |
| SmartSpectra telemetry | SDK | n/a | **Off by default** (`enableTelemetry = false`). The user can opt in from Settings. When on, the SDK sends an aggregate per-session diagnostic summary: no video, no vitals values, no identifiers. |
| Presage API key | iOS Keychain, this device only | Until "Remove" in Settings or the app is deleted | Sent only to Presage to start a session |
| SmartSpectra auth | SDK contacts Presage to start a session with the API key | n/a | Required by the SDK |
| SmartSpectra LLM Insights | The SDK auto-fires "vitals check-ins": buffered pulse rate and HRV values (no video), a fixed prompt and a session ID go to Presage, which asks an LLM | — | **On; the SDK has no switch for it** (decision 67). The app never requests or shows one; the consent screen says so. |

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


Long-press the logo (or tap it 5 times) to toggle a translucent overlay on every measuring screen. It shows the raw stream: pulse and confidence, RMSSD and confidence, blink and talking flags, the top expression, the validation code and hint with the camera image's age (`cam 0.1s`), the SDK status, and the timing markers `tQ0`, `tQ1`, `tA0`, `tA1`. Record the demo with it on for part of the video.

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

The step-by-step script for these (and everything else a device must confirm) is [`docs/DEVICE_CHECKLIST.md`](DEVICE_CHECKLIST.md).

- [ ] The camera (SmartSpectra) and mic (speech recognition) run together without audio session errors.
- [x] The confidence field name on `MeasurementWithConfidence`, and the expression category names (Data Types reference). *`confidence`, a percentage 0–100; expressions: angry, contempt, disgust, fear, happy, neutral, sad, surprise. See Decisions.*
- [ ] Whether the SDK needs network access to start, and its behavior offline.
- [ ] Whether `speech_to_text` on-device mode really avoids server recognition; if unsure, use native `SFSpeechRecognizer`.
- [ ] How best to implement **Test connection**: does auth happen at `start()` with no frames?
- [ ] How a handheld phone affects `EXCESSIVE_MOTION` frequency; adjust the copy that says "hold with both hands".
- [ ] Tune the `ScoringConfig` constants after 3–4 play-test games.
- [ ] Whether `.arterialPressureTrace` arrives at about frame rate with real beat-to-beat timing: the Proof Panel's beat BPM should track the SDK pulse and its beat RMSSD land near the SDK's (decision 63).

---

## Decisions made during build

Choices made once the real APIs were in hand. Where these differ from the sections above, these win.

### Milestone 0–1

1. **SmartSpectra SDK version and packaging.** SmartSpectra-Swift **3.4.0** (latest stable tag), added to the Runner target as a Swift Package with an exact-version pin. Flutter 3.47 uses Swift Package Manager by default, so there is no CocoaPods/Podfile. The SDK binary was built with Swift 6.2.4, so building needs **Xcode 26 or later**.
2. **Breathing metrics are not requested** (changes §5.1). Requested: `.pulseRate, .arterialPressureTrace, .hrv, .blinking, .talking, .expressions`. Breathing isn't scored anyway. More importantly, the SDK docs say LLM Insights auto-fire "once a session is running" and send buffered pulse/HRV/breathing values to Presage's LLM gateway, there is no documented switch to turn that off, and the docs say Insights need **breathing + cardio** active. Leaving breathing out removes that precondition. As a check, the bridge watches `sdk.insight` and reports `insightSeen` in the stream; the spike screen and Proof Panel show "LLM insight seen". It must stay "no" on the device before §8 can claim no vitals leave the phone. *On a device it didn't: the precondition was a misreading. See decision 67.*
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
16. **Mockups vs spec.** The mockups are the canvas's HTML sources in `docs/design/mocks/`, not PNG exports. Where they disagree with this spec, the spec wins: the room vote stays on *Call it!* (not the Verdict screen); the Lobby gains the Mild / Spicy deck picker and the on-device transcription note; Settings shows a key hint, never the saved key; E5 shows the SDK's real error code; the Leaderboard footnote says scores are wiped when a new game starts or on Wipe. Details in `docs/design/README.md`.


### Milestone 2

17. **One game page.** `GameRoot` shows the screen for the current phase. Pause and *End the show?* (E6) are drawn inside that page as overlays, not pushed routes, so the game can never get stuck behind a dismissed modal. Screens depend on the controller through `GameScope` (an `InheritedNotifier`) so they redraw on every change.
18. **Calibration details.** The quiet 20 s clock starts once the SDK reports `running`. Warm-up latency runs from the end of the host reading the warm-up to the player's first *confirmed* talk start (SmartSpectra `talking` held for 200 ms). A warm-up counts as answered after 1.5 s of silence, or moves on after 12 s (25 s while the player is still talking, decision 65). Calibration keeps adding warm-ups until the baseline is valid, and shows hints after 45 s. `baseBlinkRate` uses the whole calibration (quiet + chat); the chat-only rate is shown in the Proof Panel. *Now the chat rate, decision 65.*
19. **Blink freeze** sets `zBlink = max(zBlink, 0.6)` (§5.4 says it "counts as 0.6").
20. **Expressions.** Stress categories: surprise, fear, contempt, disgust (`ScoringConfig.exprCategories`). Each is smoothed with a 500 ms moving average before taking the window max, so one noisy frame can't spike the score.
21. **What "clean" means** (§5.5). A snapshot (~10 Hz) is clean when the SDK is running, a single face is present (not `NO_FACE_FOUND`, `MULTIPLE_FACES_FOUND` or `CAMERA_TUNING`), and a confident pulse (confidence ≥ 0.4 and validation OK when it arrived) is less than 3 s old. A window needs ≥ 60% clean snapshots and at least one confident pulse sample. "Seconds of confident pulse" add up the gaps between confident samples, each capped at 2 s.
22. **Hesitation** runs from `tQ1`, or from the end of the host's "{name}, your answer?" when the question ended on silence (so it compares fairly with warm-up latency). If the player never talks, `tA1` stands in for `tA0`. Never negative.
23. **Pause and backgrounding.** Resuming restarts the current question (its window was broken); calibration simply continues. If the app goes to the background mid-turn, the SDK and speech stop cleanly, and *Resume* restarts them.
24. **Self-healing watchdog.** While measuring, if no snapshot arrives for 6 s, the camera has sent no frame for 5 s while the SDK says it's running (decision 64), or the SDK reports `error`, the app restarts the SDK session (stop, reset, configure, start) and restarts the question. After 3 restarts, or on an auth-type error, it shows E5 (code `NO_SIGNAL` when the SDK gave none).
25. **Voice fallbacks.** Mic or speech permission denied, or on-device recognition not supported for the language, shows E2 with *Play without voice*. If recognition keeps failing mid-game, the game switches to tap-to-advance by itself and says so.
26. **Players.** Party 2–8, solo 1–8; names up to 20 characters. *Play again* keeps the roster and wipes scores; *Wipe everything* also clears names.
27. **Share results** renders a dedicated card (names, scores, awards; never question or answer text) to a PNG in memory and hands it to the iOS share sheet (`UIActivityViewController`). No file is written. The off-screen card is hidden from VoiceOver.
28. **Settings follows the mock**: one row of Paste / Remove / Test connection, where the teal button reads *Save & test* once a new key is typed. The portal link opens through a native `openPortal` call, the only URL the app ever opens. Keep-awake moved to a `sus/device` channel (`DeviceBridge.swift`) with camera permission, Settings deep link, thermal state and share.
29. **Call it! and Replay** shipped in this milestone because the controller already needed them: 10 s auto-reveal, chips cycle unset → Legit → Sus.
30. **Verdict buttons.** The primary button reads *Next question*, *Next contestant* or *See the winners*; *End turn* is hidden on the last question.
31. **Testing aids.** The controller's clock is `package:clock`, so widget tests run whole games under fake time. Tests load the real fonts (`test/flutter_test_config.dart`) so 390×844 layout checks measure text like an iPhone. `tool/swift_typecheck/run.sh` type-checks the native Swift against stand-in modules (the SmartSpectra one mirrors the 3.4.0 interface).

### Milestone 3

32. **Host voice and sounds are native** (`AVSpeechSynthesizer`, `AVAudioPlayer`) inside `SpeechBridge.swift`, because that bridge owns the audio session. Recognition is gated from the moment the host starts until 150 ms after playback ends (§7), by withholding mic buffers from the recognizer rather than stopping the audio engine. When the mic isn't in use, playback uses the `.playback` category so the host is heard even with the silent switch on; while listening it's `.playAndRecord` with `.defaultToSpeaker`.
33. **Voice choice:** the best installed English voice (premium, then enhanced, then default). Ties go to the current English locale, then en-US, then the iOS default for the locale. Novelty, personal and legacy voices (Albert, Bells, Fred, Eloquence's Eddy and others) are never picked: since iOS 17 they show up in the voice list with the same "default" quality as Samantha. iOS ships only the compact voices, so the player gets a premium voice once they download one in Settings > Accessibility > Spoken Content > Voices.
34. **No stalls from audio.** Every host call has a Dart-side timeout (speech: 2.5 s + 0.5 s per word; sounds: 6 s). On timeout the voice is stopped and the game moves on. Audio errors never surface as game errors. Sound files that are missing are skipped quietly.
35. **Host lines:** "{name}, sit still and look at the camera." (calibration), each warm-up question, "Ask your question!" (party), "Here's one for you, {name}. {question}" (solo), "{name}, your answer?" (silence path, milestone 4), "Call it! Legit or sus?", "Legit!" / "Hmm…" / "Sus!", "And the winners are…". The text always shows in the host bubble too, so it doubles as captions, and the toggles in Settings or the Pause sheet mute it.
36. **Solo timing:** `tQ0` is when the host starts reading and `tQ1` when it finishes. With the host voice off, `tQ1` comes after an estimated reading time (1.5 s + 55 ms per character). If the player starts answering before the host finishes, that ends the question early.

### Milestone 4

37. **Turn detection** (`lib/voice/turn_detector.dart`) shipped with milestone 2's controller and the app has used automatic mode since; milestone 4 adds its tests and one refinement. `TurnConfig` holds every constant.
38. **Talking debounce.** SmartSpectra `talking` must hold 200 ms to count as a talk start and be off 500 ms to count as a talk end. Confirmed times are the original edge times, so debouncing adds no hesitation.
39. **Who's speaking.** Recognized words while the player isn't talking belong to the asker and set `tQ0`. Mic level only extends asker speech that recognition has already picked up, so room noise alone can't start a question. Talking before the asker has said anything is ignored.
40. **Question end.** On the silence path, `tQ1` is when 1.5 s of silence is detected; the host then says "{name}, your answer?" and hesitation counts from the end of that prompt. The backup button ends the question without a prompt (hesitation from the tap, as §7 specifies for no-mic mode).
41. **Answer end.** 4 s after the player's last activity: a confirmed talk end, or new recognized words once they've started answering (so a dropout in the talking flag mid-sentence doesn't cut them off). If they never start, the answer ends after 20 s. No-mic mode has no automatic ends at all: *Done asking* and *Final answer* only.

### Milestone 5

42. **Sound effects are synthesized**, not downloaded: `tool/gen_sfx.py` (standard library only, deterministic) writes jingle, drumroll, ding-ding, wah-wah, buzzer and applause to `assets/sfx/` as 22 kHz mono WAV (~540 KB total). They're original work, released under CC0. The turn-start jingle finishes before the host's first line.
43. **App icon and launch screen.** `tool/gen_icon.py` draws the icon (tomato marquee board with bulbs, "SUS" in Bowlby One SC on mustard) at every size in the asset catalog, opaque as the App Store requires. The launch screen background is mustard.
44. **Accessibility pass.** Custom buttons put their tap handler on the semantics node, so VoiceOver can activate them (a test checks this). Text scale is capped at 1.3× so the fixed 390×844 layouts hold. Small cream text never sits on tomato (~4.1:1); those surfaces use the meter ramp's deeper red `#B8301D` (~5.5:1). A test checks every small-text color pair against WCAG AA.

### Milestone 6

45. **Submission docs.** `README.md` follows §15. `docs/DEV_POST.md` is a draft using the challenge's official template headings (What I Built, Demo, Code, How It Responds to Human Signals, Prize Categories, Consent and Data Handling, Agent Session), with placeholders for the video and agent-session links. `docs/DEMO.md` is the shot list with timings. `docs/DEVICE_CHECKLIST.md` collects every check that needs a real iPhone. Before submitting: make the GitHub repo public (it's private now), record the video, and fill the placeholders. Deadline Nov 22, 11:59 PM PST.


### Final verification

46. **Seams.** `test/contract_test.dart` reads the Swift sources and checks every channel name, method, argument, payload key, status/validation/error code and sound file name that Dart depends on. It also checks that every Swift file is in the Xcode target, SmartSpectra is pinned and linked, the iOS 17/iPhone/portrait settings hold, breathing metrics and Insights are never requested, telemetry is forced off, recognition is on-device only, and no Dart file touches disk, analytics or the network.
47. **Scale and performance.** An 8-player × 7-question game with every voter voting runs to the leaderboard. The signal log restarts each turn and stays far below its cap. Measured: ~1.5 µs to ingest a snapshot; ~0.5 ms to score a window.
48. **Self-healing.** Every action checks its phase and ignores a repeat within 600 ms (double taps used to be able to skip two players). A game "epoch" is bumped on every start and reset; async flows check it after each await, so a reset mid-flight can't leave the camera running in the lobby or show an empty leaderboard. The watchdog also restarts an SDK stuck in `starting`/`stopping` for 15 s. E5 *Try again* resumes at the interrupted question when the player is already calibrated.
49. **Fuzzing.** `test/fuzz_test.dart` runs 160 seeded random sessions of user actions plus failures (silent SDK, errors, bad light, sign-in failures, speech failures, permission changes, backgrounding). After every step it checks the invariants: indices in range, no duplicate or excess results, no haptics while measuring, the camera off outside turns, no uncaught errors. Afterwards it requires E5 *Try again* to work, a return to the lobby using only real buttons, and (every tenth run) a clean full game. The biased mode reports which phases it visited and fails if any screen goes untested.
50. **User pathways.** `test/pathways_test.dart` drives the real screens at 390×844 through eight full journeys: solo start to finish and wipe, everyone skips, consent Back and End the show, the lobby limits and the Proof Panel shortcut, calibration skips, no clean read then backgrounding, E5 → key settings → Try again, and E2 with the camera denied. Every screen it visits is checked against Flutter's accessibility guidelines (44 pt tap targets, labelled buttons, WCAG text contrast measured on the rendered pixels). That found the settings toggles were only 38 pt tall (the whole row is the target now), small cream text on tomato was 4.1:1 (it uses a darker tomato now) and VoiceOver couldn't activate some buttons (they carry a semantics tap action now).
51. **Visual review against the mocks.** `test/gallery_test.dart` renders all 21 screens to PNG (`GALLERY_OUT=<dir> flutter test test/gallery_test.dart`) to compare with `docs/design/mocks`. Fixes from that review: headers and badges no longer collide; the lobby shows a "Contestants" heading over a full-width Party/Solo toggle; button labels shrink to fit instead of wrapping; Call it! chips are two even columns; the Proof Panel sits over the camera so the host bubble and transcript stay visible; the E4 heading names the actual problem (wiggle, light, lost face, distance, framing); E5's steps and icon follow the error (a rejected key gets key steps, not Wi-Fi steps). The gallery draws Menlo text (Proof Panel, error codes) as blocks because the test renderer has no system fonts. On an iPhone it renders as Menlo.
52. **The camera stays put through a question.** Ask, Answer and Settle are one screen (`HotSeatScreen`) with fixed-height slots: the host line (one line, shrinks to fit), the transcript card (160 pt, text shrinks to fit and then shows the newest words), and the bottom row (92 pt). The camera card takes the rest, so it keeps the same size and place from *Ask your question!* to *Locking in the reading…*, and its native preview view isn't rebuilt between those phases. The mock's small LIVE thumbnail on 4b is gone: the answer is the measured part, so the face should stay big, and a sudden layout jump makes people move. Live pulse and blink cards sit over the bottom of the camera. *Final answer* fills the bottom row next to Pause (Pause was missing from 4b, though the §4 state machine has it there). The E3 banner slides in over 250 ms instead of snapping (since decision 69 there's no banner: nothing moves). `test/pathways_test.dart` checks the camera's position, size and native view in party and solo mode, at normal text size and at 1.3×.
53. **Pulse trend.** The Pulse card shows a small trend line for the current question next to the number, from the moment the question starts. It uses only confident readings (the same ones scoring uses) and breaks where there's a gap of more than 4 s. A dashed line marks the player's calibrated normal. The vertical scale is never tighter than ±12 BPM around that normal, so a 2 BPM wobble stays small instead of filling the chart. Time runs over at least 15 s, so the line draws itself left to right and then compresses. The number is the latest confident reading, so it matches the end of the line. The arrow and number are relative to the normal. The same Pulse and Blinks cards now show on Ask too, so the camera overlay is identical on Ask, Answer and Settle. The SDK's pulse rate is itself smoothed over several seconds, so the line lags the body a little; that's expected.
54. **Pulse chart on the Verdict and Replay.** Each result keeps its confident pulse readings with timestamps (in memory only, cleared by Wipe and Play again) and the end of its scored window. The Verdict adds a "Pulse through the question" card under the tiles. It covers exactly the window the score used (question start to at least 12 s after the question ends), with the answer shaded, the player's normal dashed, and the peak. Replay rows use the same chart instead of the old auto-scaled line, so every pulse line in the app uses the same fixed scale. VoiceOver gets a sentence: average, difference from normal, peak.
55. **Reliability pass over the session's changes.**
    - *Double taps across screens:* the existing guard only stopped the same button twice. After any phase change, taps are now ignored for 450 ms, so the second tap of a double tap can't land on what the new phase put in the same spot ("Got it" → "I agree" would have given consent by accident; "Tap when done asking" → "Final answer" would have ended the answer before it began). This applies to VoiceOver too, but 450 ms is shorter than swipe-then-double-tap. There's no guard on the first screen at launch.
    - *Bad native values:* every number from the platform channel is parsed as finite-or-null (NaN, infinity and a NaN timestamp used to reach scoring, or throw). Pulse outside 30–220 BPM (`ScoringConfig.pulseMinBpm/MaxBpm`) is dropped as a glitch. Swift skips non-finite pulse and HRV values too.
    - *Lobby settings lock:* mode, deck, question count and players only change in the lobby.
    - *Fitting text:* FitText measures with the ambient text style (Material's taller body line height), keeps whole lines only, keeps the newest words of a transcript ("…maybe once.") or the start of a question, and gives VoiceOver the full text.
    - *Small phones:* the Ask/Answer/Settle layout is tested at iPhone SE size (375×667) and 1.3× text. On a short camera the E3 chip hides (the banner says the same). The lobby's mode toggle stays on one line. The Proof Panel's bottom edge is derived from the layout's own sizes, so it never covers the live cards.
    - *Seams:* a contract test scans every code-like string the Dart code matches on and requires Swift to send it (three Dart-made codes excepted). Before, a misspelt code would fail silently.
    - *Measured:* about 25 µs of controller work per snapshot, about 5.5 ms per 100 ms of live Ask/Answer updates, and 2.2 ms per FitText update, all in debug.
56. **Camera box on small phones.** The face oval used to be a fixed share of the box (52% of the width, 68% of the height), so on a short, wide box (iPhone SE, or large text) it flattened into a circle and ran under the chips and live cards. It now keeps a face shape (0.72 wide to tall) and fits between the chips at the top and the cards at the bottom. The native preview fills its box and crops, and in a very wide box it would show only a thin band of the portrait camera image, too thin for a face at a normal distance. Past 1.1 wide to tall, the video is pillarboxed: ink bars at the sides, the overlay still full width. Standard iPhones don't hit that limit. The video now sits inside the 3 pt border; the border used to be painted behind the video, so on a phone the video would have covered it and its corners would have poked past the card's rounded edge. The widget tree doesn't change when the bars appear, so the native preview isn't rebuilt.
57. **Second reliability pass (camera card).**
    - *Real safe areas in tests:* the test rig now gives the view an iPhone's status-bar and home-indicator space (iPhone 14: 47/34 pt; iPhone SE: 20/0). Before, every test and screenshot had about 81 pt more height than a real iPhone 14. Measured with it, the Ask camera box is 354×353 on an iPhone 14 (342 tall at 1.3× text) and 339×237 on an SE (226 at 1.3×).
    - *Calibration on small phones:* on an SE at 1.3× text the calibration camera was so short the face oval shrank to 4 pt. The live pulse card (with the waveform) moved from under the camera onto its bottom edge, the same card and place as on Ask and Answer, which gave the face about 100 pt back. The calibration chips stay on one row (they used to wrap).
    - *Nothing sits in the oval's space:* the oval keeps clear of the top chips by their measured height at the current text size (it used to be a fixed 42 pt, wrong at 1.3×). "Picks up again when it's clear" now replaces the live cards while the reading is paused (their numbers are frozen then); "{name} is talking" sits inside the calibration card. Tests check points along the oval against every chip and card, in calibration, Ask, Answer and E3, on both phones at both text sizes. With the E3 banner on an SE at 1.3× there's no room for an oval, so it hides and the banner gives the guidance.
    - *Native preview:* it resizes with its box (bars, banner), so the selfie mirror now flips each image's orientation instead of transforming the view (a transformed UIView's frame is undefined). It's a flag change with no pixel copy. A contract test keeps it that way.
    - *Fakes match the bridge:* the test SDK fakes now send `talking` in every snapshot and a talk edge only when it changes, as the Swift bridge does. Before, "{name} · talking" and the calibration talking chip never showed in tests. A contract test checks the fakes send the bridge's snapshot keys.
    - *Measured:* Ask/Answer costs 5.7–6.2 ms per 100 ms of live updates in debug, now including the talking indicator. Chip height is cached per text size.

### Play-testing

58. **Solo keeps the question up.** The screen used to switch to the answer card the moment the host finished reading, while the player was still taking the question in. Now the solo question card stays until the player starts talking (camera), is heard (recognized words), or taps *Ready to answer* (next to *Different question*, which also works until then). Only the screen waits: `tQ1` is still when the host finished, so hesitation, the 12 s window and the 20 s no-answer timeout are unchanged. Tapping *Ready to answer* while the host is still reading stops the voice and ends the question there, like starting to talk early (decision 36); the native bridge reopens the mic 150 ms after the cancelled utterance, as for any host line.
    - *One source of truth:* `GameController.shownPhase` is Ask while the question is held. `HotSeatScreen` and the 450 ms tap guard (decision 55) both read it, so the guard also covers *Ready to answer* → *Final answer*, which swaps buttons without a phase change. A widget test double-taps it.
    - *Prompt redraw:* when talk or words end the hold, the controller notifies straight away rather than on the next 100 ms tick.
    - *Repeats:* *Different question* ignores a repeat within 600 ms, so a double tap skips one question, not two.
    - *Seams and scale:* the camera test from decision 52 covers the hold in solo (same size, place and native view through Ready). A solo 8 × 7 game releases the hold every way (button, camera, mic) and checks it never leaks into the next question or player. The fuzzer taps *Ready to answer* too.
    - *Measured (debug):* the hold check is ~45 ns; the held screen redraws at the same cost as the Ask screen it extends (~7–10 ms per 100 ms in the test renderer, most of it FitText re-measuring the question).
59. **Lobby names and choices.** Contestant names, in the rows and as they are typed, use the display face (Bowlby One SC, 21 pt) like the "Contestants" heading, instead of 17 pt Work Sans, so a name carries the same weight as the rest of the game show. A long name shrinks to fit its row rather than ending in "…". The Party / Solo switch, questions per turn and deck are now rows of separate tiles. The picked tile is 1.3× as wide, 56 pt tall instead of 46, with larger text, so the choice shows by size as well as by color. The change animates over 180 ms, or instantly with Reduce Motion. Every tile's tap area is the full 56 pt row height. The placeholder stays in Work Sans, as in the mock. This differs from `Main.dc.html`, where the mode switch is one joined pill and the picked option is only recolored.
60. **Fewer repeats of the player's name.** The answer screen showed the player's name in the header pill, the host line, the transcript label ("Sam · talking") and the camera chip ("Measuring Sam"). Now it's in the two places that do a job: the pill, which says whose turn it is for the whole turn, and the host line, which captions what the host says out loud (decision 35), where a name is how you call on one person in a room. The transcript label is by role, "Hot seat · talking" / "Hot seat · listening", matching "Asker · listening" in the same slot on Ask, and the camera chip is just "Measuring", since it's the player's own face in the frame. Ask and Settle lose the name from the chip too. The warm-up screen gets the same trim: the title "Warming up {name}" stays, and the talking indicator in the pulse card says "Talking" instead of "{name} is talking". The mocks (`Question.dc.html`, `Question-Solo.dc.html`, `Answer.dc.html`, `Calibrate.dc.html`) still show the name.
61. **Numbers on the Replay pulse line.** The Replay sparkline had no numbers, so it was hard to tell what it showed. A row under it now gives the player's normal, next to the same dashed swatch as the Verdict legend ("normal 84"), and the highest reading ("peak 95 BPM", as in the Verdict card's header). We considered the first and last readings, but the window runs at least 12 s past the end of the question, so the pulse has often settled again by its end, and a spike in the middle would get no number. VoiceOver reads the row as one sentence. The answer band stays unlabelled here; the Verdict legend explains it.
62. **Expression #tag on the camera.** SmartSpectra gives a confidence for each of eight expressions (angry, contempt, disgust, fear, happy, neutral, sad, surprise), not a single label. The camera now shows the strongest one as a rubber-stamped #tag in the SDK's own words, in Bowlby One SC (mock: `docs/design/mocks/ExpressionStamp.png`, placement A).
    - *Steady:* `ExpressionTagger` smooths each score with a 600 ms exponential average and changes the tag only once a new leader has held for 700 ms. Raw scores arrive about every 100 ms and close ones trade places, so without this the tag would flicker. A new tag must also lead the runner-up by 0.05: in a close call which one leads is arbitrary (a tie would otherwise go to the first label alphabetically, found in review), so it never brings up a tag, and a tag already shown stays while it's one of the two, rather than blinking off and on as the gap hovers at the margin.
    - *Honest:* no tag when no smoothed score reaches 0.3, or after 1 s without a usable face (SDK not running or validation not OK) or without fresh expressions (the bridge resends the last scores between SDK updates; `exprAt` says when they last changed, and over 3 s old counts as no reading). Only the eight known categories count: the bridge's fallbacks (`unspecified`, `unknown<n>`) never become a tag. On Ask/Answer it also hides while the E3 banner is up. It's the raw reading, not relative to the player's baseline (the score is), so it's for show only. A player whose resting face reads as *sad* may sit on #sad.
    - *Look:* a solid block of ink with an inset cream frame and the tag knocked out in cream, worn in spots (specks, edge nicks, dry streaks, a fixed pattern per tag) so the camera shows through, tilted −8° to +5° depending on the tag. Red ink (`tomatoDeep`) for the four expressions the score counts (`ScoringConfig.exprCategories`), teal for the rest; cream on either is ≥ 4.5:1 for small text. A new tag drops in like a stamp (scale 1.55 → 1 with an ease-in, 200 ms); the old one fades (150 ms). With Reduce Motion it just appears. VoiceOver reads "Expression: surprise", not "number surprise".
    - *Place:* top-right corner of the camera. On Ask/Answer/Settle it shares the top row with the *Measuring* chip (42% of the row for the stamp, so at large text sizes the chip shrinks rather than running under it) and hangs down over the oval's top-right edge. On Calibrate it sits just under the two status chips, at the same width and right edge. It may cover the oval's edge (it's stamped on the picture) but stays clear of the chips and live cards; `test/pathways_test.dart` checks that in party and solo, at 390×844 and 375×667, at 1× and 1.3× text. The lower-right corner was the alternative; it covers the chin and mouth, where expressions show. Changing the tag never rebuilds the native camera view (checked mid-answer).
    - *Seams:* the bridge now sends `exprAt` (milliseconds, like `pulseAt`) with each snapshot once an expression sample has arrived; it's cleared with the other measurements on start and stop. `test/contract_test.dart` checks Swift emits it, the fakes send `expr` and `exprAt`, the names in `PresageBridge.expressionName` are exactly the tagger's eight labels, and every scored category is one of them. The tagger is reset when a session starts (`_startSdk`), when measuring stops, when the app is backgrounded, and on every move to a phase without the camera, so one player's tag never shows for the next. A review found it used to linger into the next player's Calibrate: the signal log was cleared per turn, the tagger wasn't, and after the SDK stops no snapshot arrives to clear it. `test/game_controller_test.dart` replays that hand-over, and the fuzzer now requires no tag in any camera-off phase. With the resets removed, both fail.
    - *Performance:* a fixed 8-slot array, no allocation per snapshot: about 155 ns per snapshot (JIT, measured in a cloud container); `test/scale_perf_test.dart` holds it under 5 µs over 600,000 snapshots and runs it inside the 10 Hz controller stress test. A game adds no state: one tagger, reset each turn. The stamp has its own repaint boundary, so while the tag is unchanged the 10 Hz overlay rebuild doesn't repaint it (a pathways test counts its paints over a second of updates). Its worn-ink layer is drawn only when the tag changes.
63. **Pulse from heartbeats, compared with your other answers.** The SDK's pulse number is a 12 s average (Presage's model card), so a reaction lasting a few seconds is smeared and late, and the mean over the window throws away its shape. The bridge already requested the pulse waveform (`.arterialPressureTrace`, decision 3) but only drew it.
    - *Seams:* the bridge now sends each waveform sample's SDK timestamp (`traceTs`, microseconds) and confidence (`traceConf`, 0..1) next to `trace`, and skips non-finite values so the three lists always line up. Dart pairs them only when the lengths match, so an older bridge just means no beats. `SignalLog` keeps the timestamped waveform for the whole turn (up to 60,000 samples, about 33 min at 30 Hz) and maps the SDK clock to wall time by the smallest delay seen between a sample and the snapshot that carried it; every sample on the same clock uses the latest estimate, so a first batch that arrived late is corrected once the next ones show the real delay. A late snapshot only looks like a longer delay and changes nothing. A new mapping starts only if the SDK clock itself jumps by over 2 s: it goes back while the wall clock doesn't (a restart), its next sample is further ahead of the previous one than the wall clock moved (a jump forward), or its newest sample is further behind than the wall clock moved (it paused, e.g. a monotonic clock while the phone slept). A stall doesn't look like any of these, because the samples made meanwhile arrive together. If the bridge turns late and stays late, the waveform follows the new delay, staying lined up with the pulse readings and frames, which are stamped on arrival too. A sample's `ok` comes from the snapshot that carried it, so it lags the sample by the delivery delay (about 150 ms). Samples that are just old, with the same offset, are dropped as repeats. Samples carry the snapshot's validation gate, like pulse readings. `traceConf` is shown, not used as a gate, until we've seen what values it takes on a device.
    - *Beats* (`lib/game/beats.dart`): pieces of good waveform with no gap over 0.3 s and at least 4 s long are resampled to 30 Hz and band-passed (2nd-order Butterworth high- and low-pass at 0.7 and 3.5 Hz, run forwards and backwards, with odd reflection at the ends). A beat is a peak above zero at least 333 ms (180 BPM) after the previous one and at least 35% of the median nearby peak, timed between samples by a parabola through the top three. Intervals outside 40–180 BPM, or more than 30% from the median of their neighbours, are kept but marked not accepted (a missed or extra beat). Heart rate holds from one beat to the next, so averages are time-weighted. Polarity doesn't matter for timing: one peak per beat either way.
    - *Shape:* for each question window, the level is the mean beat rate over the 5 s before `tQ0` (15 s if that's under half covered), so drift during a turn cancels out. **Rise** is the highest point of the rate smoothed over 3 s (about one breath, so breathing's own swing mostly averages out) above that level; **ran high** is the mean over the window above it; **early slowdown** is the level minus the lowest smoothed point in the 6 s after `tQ1`. A brief slowdown after a pointed question is the heart-rate response concealed-information studies most often report; heart rate is their weakest channel (Meijer et al. 2014, *Psychophysiology*: d* ≈ 0.89, against 1.55 for skin conductance), hence its 0.2 weight. Recovery after the answer isn't used: the window often ends soon after `tA1`.
    - *Compared with the player:* each feature is ranked against the same player's answered warm-ups (their timing is now kept as `PlayerTurn.warmupTimings`, and their shapes are found once and cached as `warmupShapes`) and earlier scored questions in the turn. A warm-up's window ends where the next warm-up, or the first question, starts: with the usual 12 s after the question it ran into Q1, so a racing Q1 raised its own references (zPulse 0.28 instead of over 0.6). Each feature's score is its distance above their median in robust spreads (1.4826 × MAD, at least 4 / 3 / 3 BPM so a player whose answers were all alike doesn't turn a wobble into a spike), clamped to 0..1 at 2.5 spreads. `zPulse = 0.4·rise + 0.4·ran high + 0.2·slowdown`, still weighted 0.45 in the score. The warm-ups include talking, as the questions do, so speaking's own effect on heart rate mostly cancels. The rise of a longer answer has more chances to peak, so it's biased slightly up against short warm-ups; play-testing should say whether that matters.
    - *Trust:* beats are used only if they cover ≥ 60% of the window, the median difference between each confident SDK reading and the beats' average over the 12 s before it is ≤ 8 BPM, and ≥ 2 of the player's warm-ups pass the same checks. Earlier questions add to the comparison but can't stand in for warm-ups: otherwise a player who skipped both warm-ups would be scored by the SDK mean for Q1–Q2 and by beats from Q3, two scales in one turn. A single question with poor beats still falls back on its own. The SDK's reading may arrive a few seconds after the beats it averages; without allowing for that, a +35 BPM jump with a 4 s delay read as 10 BPM off, so the biggest reactions were the ones sent back to the old formula. The check tries one delay for the whole window, 0–6 s in 1 s steps, and keeps the best; a steady offset (beats at 82, SDK at 70) still fails. Otherwise the original SDK-mean `zPulse` is used, and `ScoreBreakdown.pulseNote` says why. The stat tiles and pulse charts still use the SDK readings.
    - *Proof Panel:* waveform samples per second and confidence; beat rate, beat RMSSD and coverage over the last 12 s (updated once a second, only while the panel is on); and the last score's method with each part's 0–1 score and the raw BPM. On a device, the beat rate tracking the SDK pulse and the beat RMSSD landing near the SDK's RMSSD would show the waveform holds real beat timing, not a smoothed template.
    - *Cost:* each question searches only its own window plus 20 s before it, about 2 ms (JIT, in a cloud container) however long the turn has run; the warm-ups are searched the same way once per calibration and cached on the turn. An earlier version searched from the first warm-up on every question, which took 92 ms once the waveform store was full (60,000 samples). The live readout searches 35 s once a second, about 1 ms, only while the Proof Panel is on. Ingest is about 35 µs per snapshot with the waveform.
    - *Swift:* `tool/swift_typecheck/run.sh` passes with Swift 6.2 against the stubs (and fails on a deliberately wrong type in the new lines).
    - *Tests:* `test/beats_test.dart` runs synthetic waveforms (45–150 BPM, 15–60 Hz, a jump, breathing swings, heavy noise, a dropped beat, bad-validation gaps; SDK clocks that are offset, restart or jump ahead; a stalled bridge, a late first batch, a bridge that stays late) and fuzzes the store and the beat finder with random times, values and list lengths. `test/fuzz_test.dart` now also turns the waveform on and off, mangles SDK timestamps (jumps both ways, reversed, repeated, wrong length) and toggles the Proof Panel, and checks every score says how its pulse was worked out (both methods occur). `test/scale_perf_test.dart` holds a question at ≤ 25 ms at the full store, a 10 Hz stream with the waveform and the Proof Panel on, and 4 players × 7 questions all scored by beats. `test/pulse_shape_test.dart` checks each shape feature, the ranking and its floors, every fallback reason, and a whole game in `World`, which can now beat a waveform whose SDK pulse is its 12 s average like the real SDK's. `World` is deliberately less kind than an ideal SDK: its SDK pulse is the 12 s average ending 2 s ago, and waveform delivery varies from 150 to 270 ms. Untested on a device so far: whether `.arterialPressureTrace` arrives at frame rate with real beat-to-beat timing. The cross-check compares rates, so it can't tell real beats from a waveform the SDK draws from its own smoothed pulse; that would pass, and the shape features would then just follow the smoothed pulse (no worse than before, no better). The Proof Panel's beat RMSSD against the SDK's is the check for that.
64. **A frozen camera is restarted.** On a device the camera preview stalled mid-question on a shaky frame and never moved again: the SDK still said `running`, so the bridge kept sending a snapshot every 100 ms with the last validation code (`EXCESSIVE_MOTION`). The watchdog only looked for missing snapshots, so it never stepped in, and *Reading paused · Picks up again when it's clear* stayed up for good. Pause wasn't the cause: it doesn't touch the camera.
    - *Seams:* the bridge now sends `frameAt` (milliseconds, like `exprAt`): when the SDK last published a camera frame (`imageOutput`, observed the same way the preview does), or when it started running if that's later, so a camera that never delivers a first frame counts too. It's cleared with the other measurements on start and stop.
    - *Watchdog:* while measuring and not paused, a `running` snapshot whose frame is over 5 s old restarts the SDK and the question, like a silent SDK (decision 24); after 3 restarts it's E5 with "Lost the signal: the camera froze." Frame age is taken within one snapshot (`t − frameAt`), so a snapshot left over from before a pause or the background can't set it off. A camera that froze during Pause is restarted as soon as Resume is tapped. Every restart path (watchdog, *Try again*, Resume after the background) now clears the last snapshot, so nothing from the old session carries over.
    - *Inactive app:* Control Center, Notification Center, the app switcher or a system alert makes the app inactive, and iOS may hold the camera until it's back. The frame check rests while the app is inactive and for 5 s after it's active again; otherwise reading a notification for 20 s could run up three restarts and E5.
    - *Proof Panel:* `cam 0.1s` after the validation code. It should stay under a second; a climbing number means the camera has frozen.
    - *Why the SDK's camera stalls* is still unknown (it happens inside SmartSpectra or AVFoundation). The device checklist asks to note when it happens.
    - *Tests:* the test SDK sends `frameAt` and can freeze its camera; `test/game_controller_test.dart` checks a freeze restarts within 5–6 s and clears *Reading paused*, a camera that stays frozen ends in E5 instead of hanging, a freeze during Pause is fixed on Resume, and an inactive app is left alone (without that guard it restarted 3 times). Without the watchdog change all of them fail. The fuzzer now freezes the camera and makes the app inactive at random, and both 8 × 7 scale games check there's exactly one camera session per player, so a healthy camera is never restarted.
    - *Cost:* one `Task` hop on the main actor per camera frame in Swift (the preview already does the same), one more integer per snapshot, and a subtraction per 100 ms watchdog tick in Dart. The Swift stand-ins weren't run here (no Swift toolchain in the cloud container); run `tool/swift_typecheck/run.sh` before an Xcode build.
65. **A calm, honest answer scores near 0.** On a device, truthful answers were coming out Sus even though the heartbeats were good. Simulating calm answers through the real code showed why: with nothing changed since the warm-ups, the average score was 35 (the Hmm line) and half were Hmm; an ordinary honest answer (longer to think about and to say than "coffee or tea?", one smile) was Sus a third of the time and Legit 5%. Every part could only push the score up, and three of them were tilted:
    - *Blinks:* blinks come at random, so a 15 s window's count wobbles by about √n even when nothing changed, and only increases counted. The 6 s "freeze" fired by chance in about half of all answers at a normal 17/min. And the baseline mixed 20 s of sitting still with chatting, though people blink more talking. Now the baseline is the warm-up chat rate (calibration now chats for at least 15 s, `calibMinChatMs`, and ends only between warm-ups; a shorter chat falls back to the whole calibration), with how long it was counted (`Baseline.blinkBaseMs`); the score counts blinks beyond expected + one chance wobble, √(expected × (1 + window ÷ baseline span)), over 0.6 × expected (expected uses at least 6/min). A freeze must be longer than the gap that would turn up in the window by chance 1 time in 20 at the player's rate, g = ln(rate × window ÷ 0.05) ÷ rate, and never under 6 s (`Scoring.blinkFreezeMs`). At 17/min in a 15 s window that's 15.7 s, so it can't fire; at 40/min it's 7.9 s.
    - *Expressions:* the window's smoothed *peak* was compared with the calibration *mean*, and a peak is always above its mean. Now it's compared with the warm-ups' own peak (`Baseline.exprPeak`), smoothed over 1 s, with the first partial second ignored so one frame can't count in full; scale 0.3. And SmartSpectra scores a smile as contempt too (seen on the device: #CONTEMPT at 39% on "a word that makes you smile"), so each stress expression counts only by how far it's above happy in the same frame (`ScoringConfig.exprSmile`): a tie is a smile.
    - *Hesitation:* warm-ups are easier than real questions, so 1 s of extra thinking is free (`hesitationGraceS`).
    - *Pulse:* the beat shape's ranking gives the first robust spread free (`shapeZFree`), still full at 2.5 spreads: a 4 BPM talking wobble no longer counts, a 12 BPM rise counts the same as before.
    - *Warm-ups ask for a sentence* ("Tell me what you had for breakfast today"), so they're compared with real answers on similar talking, and a warm-up waits up to 25 s while the player is still talking (`calibWarmupTalkingMs`).
    - *Calibration ends between warm-ups only.* It used to end the moment the baseline turned valid, which could be while the host was reading a warm-up or the player was answering one, so question 1 started on top of it (and longer sentence answers made that likelier). Now it ends when a warm-up finishes (answered, skipped or timed out) and the baseline is valid, ≥ 2 warm-ups are done and the chat has run ≥ 15 s; otherwise it asks another. The baseline is recomputed at that moment, not taken from the last 500 ms check.
    - *Kept:* weights, the `^0.8` curve and the verdict bands.
    - *Tests:* `test/calm_answers_test.dart` runs 1,500 made-up players per scenario through the real baseline and feature code (blinks at random, expression noise with ~1 s memory, latency spread, beat shapes drawn alike for warm-ups and questions). Nothing changed: ~93% Legit, 0% Sus. Ordinary honest answer: ~84% Legit, 0% Sus. A clear reaction (+12 BPM rise, +8 mean, 3 s pause, 40 blinks/min, a surprise/fear burst): ~83% Sus. A racing heart alone: mostly Hmm. A smile scored as contempt changes the mean by under 1.5. A short warm-up chat (9–24 s) keeps false freezes at 2–4%. `test/seams_test.dart` runs both fixes through the real controller and bridge maps: a frequent blinker's honest, smiling answer is Legit and stamped #happy (the old code scored it 50, Hmm…, with no tag), and a 16 s warm-up answer isn't cut off while a stuck talking flag still moves on at 25 s. Both fail on the old code. The noise levels are assumptions, not device measurements. Pulse alone can't reach Sus (0.45 of the raw score), so the 8-player scale test now stresses every third answer on two signals.
66. **The #tag's close calls go to the happier expression.** A tie between, say, happy and contempt used to show no tag (or keep the one shown), so a smile the SDK also read as contempt could stay stamped #contempt. Now a close call (inside the 0.05 margin) between expressions of different positivity (happy, then neutral and surprise, then angry, contempt, disgust, fear, sad) goes to the happier one, for bringing up a tag and for switching. Close calls within the same group keep the old rule.
67. **LLM Insights are on, and the SDK can't turn them off.** On a device the Proof Panel showed "LLM INSIGHT SEEN". Presage's v3.4.0 docs (`docs/llm-insights/index.md` in Presage-Security/SmartSpectra at tag v3.4.0) say that once a session runs, the SDK "automatically dispatches vitals snapshots of the accumulated metrics buffer: one the first time pulse rate has a stable reading, one when breathing rate does, one when HRV does, and then one every 60 seconds", with its own fixed prompt. The "breathing and cardio must both be active" line decision 2 relied on is under the heading about when insights are *meaningful*, not what triggers them. What's sent: an allowlisted series of pulse rate, HRV and breathing rate (so pulse and HRV here), the prompt and request metadata (session ID, origin, request ID); "raw video and facial imagery are never transmitted". `SmartSpectraConfig` 3.4.0 has no insights switch (`enableTelemetry` is separate), so the only way to stop it would be to stop measuring the pulse.
    - *Disclosure:* the consent screen now says "Your pulse numbers (not video) go to Presage for an AI check-in", "Processed on this phone" became "Video is processed on this phone", and README, §8 and the DEV post say what's sent.
    - *Proof Panel:* the bridge counts each new insight (by request ID and time) and keeps only what the last one was: answered (with the text's length), error (with its message, e.g. an HTTP status; a transport error may mean nothing left the phone) or empty. The panel shows "LLM INSIGHT ×n (answered, 412 chars)". The text itself never crosses the bridge. No insight seen doesn't prove nothing was sent: the service may return no analysis for a snapshot.
    - *Stub:* `tool/swift_typecheck/stubs/SmartSpectra.swift` now mirrors the real 3.4.0 `Insight` (`requestID`, `processedAt`, `result` with `.analysis`/`.error`, `type`). Not type-checked in this session: no Swift toolchain was available.
    - *Open:* ask Presage (support@presagetech.com) for a way to turn auto-fired insights off.
68. **Replay names.** With one contestant (solo mode, or a show ended after the first turn), the Replay showed a single ink tab: a picker with nothing to pick, which read as a stray button, and the smallest name type in the app. Now one contestant gets a name line instead (teal initial, name in the display face, "4 questions"), like the Lobby's player rows. Two or more keep the tabs, which now carry the same teal initial, with names at 15 px instead of 14. The gallery adds `07b-replay-tabs` for the tab row.
69. **Camera problems are stamped on the camera.** The E3 banner slid in above the transcript card whenever a problem lasted 1.5 s, pushing the transcript and the camera down by about 100 pt and shrinking the face oval, then slid back out when it cleared. Hand-held, "Hold still" came and went, so the screen kept jumping, which is the opposite of what it asked for (decision 52: a layout jump makes people move), and it moved the oval the player was told to line up with. The player is looking at their own face, so the problem now goes there.
    - *Look:* a rubber stamp like the expression #tag (decision 62), in the same top-right slot, which is empty during a problem anyway. Mustard ink with ink letters, so it reads as a warning from the show, not as a reading of the player (red and teal are the expressions'). It drops in like a tag, and a tag and a problem with the same words are still different stamps. With Reduce Motion it just appears.
    - *Words:* each problem has a stamp of one to three words, short enough to read at a glance: *Too dark, Too bright, No face, Too many faces, Move closer, Move back, Off center, Look here, Hold still, Lagging, Adjusting*. The longer titles stay for VoiceOver and the calibration hint. While a problem shows, the stamp gets 54% of the top row instead of 42% ("Reading paused" is short). Even the longest, *Too many faces*, is drawn at about 15 pt or more on an SE and an iPhone 14 at 1× and 1.3× text (`test/pathways_test.dart`); the others fit at full size.
    - *Fix:* the fix ("Rest your elbows or prop the phone up.") takes the live cards' row, where "Picks up again when it's clear" was. "Reading paused" stays in the top-left chip, so the dark-room fix drops its own "Reading paused."
    - *VoiceOver:* the stamp is a live region reading the full title and fix ("Can't see a face. Get your face inside the oval."), as the banner was. The fix chip is excluded so it isn't read twice.
    - *Tests:* the camera test from decision 52 now raises a problem mid-answer and checks the camera's rect and native view and the transcript card's place don't change, the oval stays clear of the chips, the stamp stays inside the camera and clear of them, and it clears again. The no-clean-read pathway checks the stamp, its fix, its VoiceOver label and the screen's accessibility guidelines (contrast included).
    - *Calibration* gets the same stamp, under the status chips where its #tag goes, from the start (before, only the face and light chips showed a live problem; motion, distance and framing waited for the 45 s card), with the fix in the pulse card's place while the reading is paused. The "Still calibrating" card, which slid in after 45 s without a clean baseline and pushed the camera down, is gone: its hint is a stamp now too, the commonest problem of the last 5 s, or *Hold steady* ("Keep your face in the oval and hold the phone steady.") when none stands out (`SignalIssue.forSlowCalibration`). The reading isn't paused for that, so the pulse card stays. The hint used to stay up for the rest of calibration; now it goes as soon as the baseline is good, even while the warm-ups finish. `STILL_CALIBRATING` joins the codes Dart makes up itself in the contract test. A new pathway holds a face off center through the 45 s, fixes it, and checks the live stamp, the hint, *Hold steady*, its VoiceOver label and that nothing comes between the host line and the camera. The host line itself still grows from one line to two when the warm-ups start, which moves the camera once (unchanged here). The gallery adds `03b-calibrate-bad-signal`.
    - *Reliability pass:*
        - *Lingering problems:* the live problem was only cleared by a clean snapshot, never when the camera stopped or a session started. Calibration now shows it too, so Alex's warm-up could open on Sam's "Hold still" until Alex's first frame, and a problem could outlive the camera into the lobby. The fuzzer's new invariant caught that in 2 of 160 runs. The problem is now forgotten together with the #tag (`LiveState.resetCamera`) at the same five places: a phase without the camera, a new session, stopping measuring, backgrounding, and a snapshot that arrives with the camera off. The calibration hint is dropped whenever the game leaves calibration. `test/game_controller_test.dart` replays the hand-over with a slow first frame, and the fuzzer requires no problem in a camera-off phase and no hint outside calibration. Without the fix, both fail.
        - *Steady under a shaky hand:* a problem showed once it had lasted 1.5 s, then vanished on the first clean frame. With 2 s of motion and 0.3 s of stillness, the stamp dropped in and out 8 times in 18 s, swapping the live cards for the fix each time. Now, once shown, it stays until the picture has been clean for 1 s, and a different problem takes over with no gap once it has lasted 1.5 s (`LiveState.updateIssue`). The same run now changes the screen once. The cost is that "Reading paused", the stamp and the fix stay up to 1 s after the reading has resumed. Scoring is unchanged, since it reads validation per frame. VoiceOver also hears the problem once, not on every flicker.
        - *Seams:* a contract test reads Swift's `validationName` and requires every named code it can send to map to its own stamp (≤ 14 characters, with a fix) or to nothing (`OK`, `CAMERA_TUNING`, `CHEST_NOT_VISIBLE`). Only a code from a newer SDK (`CODE_<n>`) falls back to *Adjusting*. Breaking one mapping fails it. No Swift or channel change: the stamp reads the validation code the bridge already sends.
        - *Performance:* the problem stamp has the #tag's repaint boundary; a pathway counts its paints over a second of 10 Hz updates and finds none while it's unchanged. Measured in debug, in the test renderer, over 5 s at 10 Hz: Answer costs 4.6–5.2 ms per 100 ms with a problem showing, against 5.9–7.6 without. Calibration costs 6.2–7.3 against 9.4–11.6. A problem replaces the live cards and waveform with one static chip, so it costs less. The problem state is three fields, constant work per snapshot. The calibration hint scans the last 5 s of frames (about 50) every 500 ms, only after 45 s without a baseline, as the old card did.
