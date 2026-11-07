# On-device checklist

Everything below needs a real iPhone; the rest is covered by `flutter test`. Work top to bottom,
noting anything that doesn't match. About 20 minutes.

**Setup:** iPhone on iOS 17+, Xcode 26+, a Presage API key, good light in front of you, and a
friend for the party-mode part.

## 1. Build and sign in

- [ ] `flutter pub get`, open `ios/Runner.xcworkspace`, set your signing team, `flutter run`.
  **If the build fails, copy the first error.**
- [ ] The app icon is the red "SUS" marquee and the launch screen is mustard.
- [ ] Gear → paste your key → **Save & test**. Allow camera access. Expect **Connected** and
  "Signed in to Presage in X s". **Note X.**
- [ ] Paste a deliberately wrong key → **Save & test** → **Key rejected** plus an error code.
  **Note the code.** Then put the real key back.

## 2. Signal check (camera + mic together)

Settings → **Signal check** → **Start both**. Allow microphone and speech recognition.

- [ ] The camera preview appears. **Is it mirrored like a selfie?** (Raise your right hand; it
  should appear on the right.)
- [ ] BPM appears within ~20 s and "updated … s ago" keeps refreshing.
- [ ] Blinks count up; *Talking* says **YES** while you speak.
- [ ] Validation reads **OK** in good light. Cover the camera: it changes, and returns when uncovered.
- [ ] Speak: the transcript updates **while** the pulse keeps updating. (This is the milestone 1
  pass condition: camera and mic working at the same time.)
- [ ] After ~90 s: HRV shows a value, and **LLM insight seen** still says **no**.
- [ ] Any red error text at all? **Copy it.**

## 3. Voice host and sounds

- [ ] With the silent switch **on**, start a game: the jingle, then the host's voice, are audible.
- [ ] In a party round, the on-screen question **never** includes the host's words ("Ask your
  question!"), so half-duplex works.
- [ ] Countdown has a drumroll; Legit dings, Hmm… goes wah-wah, Sus! buzzes; the leaderboard
  gets applause.
- [ ] Haptics on the countdown and verdict, **never** during calibration or a question.
- [ ] Pause → *Host voice and sounds* off mutes everything.

## 4. A party game (2 players, 3 questions)

- [ ] Lobby → Start the show → How to play → Consent → calibration completes on its own in about
  30–60 s. (If a mustard stamp stays on the camera, note what it says.)
- [ ] A friend asks a question: it appears as they speak. Stop talking and wait: after ~1.5 s
  the host asks "{name}, your answer?"
- [ ] Next question: answer **immediately** after it's asked. The question should end the moment
  you start (no host prompt).
- [ ] After answering, stay quiet: the answer ends by itself after ~4 s, then "Locking in the
  reading…".
- [ ] From *Ask your question!* to *{name}, your answer?* to *Locking in the reading…*, the camera
  card doesn't move, resize or flash black.
- [ ] The Pulse card's trend line: roughly flat around the dashed line while you sit calmly, rising
  after a few seconds if you hold your breath or do 10 squats first. **Does it look jumpy?** The
  number should match where the line ends.
- [ ] Double-tap *Tap when done asking* fast: the answer must **not** end by itself (the second
  tap lands where *Final answer* appears). Same with *Got it, let's play*: you should still see the
  consent screen.
- [ ] Verdict: the pulse chart's shaded stretch lines up with when you were talking.
- [ ] The camera card has a visible dark border around the video, with rounded corners.
- [ ] **Expression #tag:** a stamp like *#neutral* lands in the camera's top-right corner about a
  second after measuring starts. Pull a big surprised face and hold it: it changes to a red
  *#surprise* within about a second, and back when you relax. **Does it flicker between two tags
  while you sit still?** Smile: a teal *#happy*. Cover the camera: it's gone within about a second.
  It never covers the middle of your face, and it stays readable against a bright wall behind you.
  **With the Proof Panel on, does the `expr` line change several times a second?** (The tag
  treats expressions older than 3 s as no reading; if they update less often than that, note the
  rate.)
- [ ] The preview is still mirrored like a selfie (raise your right hand: it's on the right of the
  screen), and still fills its box while a "Too dark" stamp comes and goes.
- [ ] Sit so your face fills the oval: no "Move closer" or "Move back" stamp. **If there's a
  small iPhone (SE/mini) around, try it there too, and with Larger Text on.**
- [ ] **Heartbeats** (Proof Panel on, sit still during calibration):
  - The `wave` line says about **30/s**. **Note the number and the conf %.** (`--` or 0 means
    the bridge isn't sending waveform timestamps.)
  - After ~20 s, `beats` shows a BPM within a few of the SDK's `pulse`, and `cover` is 80%+.
  - After ~90 s, the beat `rmssd` is roughly near the SDK's `rmssd` (within about half). **Note
    both.** If the beat RMSSD stays near 0 while the BPM matches, the waveform is a smoothed
    template without real beat timing, so the beats add nothing and the score will keep using the
    SDK mean.
  - After the first question, the `Q1 pulse by …` line says **beats**. If it says SDK mean,
    **note the reason in brackets.**
- [ ] Call it! → tap your friend's chip (Legit/Sus) → Reveal → countdown → verdict.
- [ ] Do the verdicts feel plausible? A calm answer should usually be Legit, and a jump-and-shout
  should be higher. **Note a few scores.**
- [ ] Leaderboard → **Share results** opens the share sheet with an image (names and scores only,
  no question text) → **Watch the replay** shows each Q and A with a sparkline, its normal and its
  peak BPM.

## 4b. Solo (1 player, 3 questions)

- [ ] After the host reads the question, **wait about 10 s without talking**: the question card
  stays up, with *Different question* and *Ready to answer*. The camera doesn't move or flash.
- [ ] Start talking without tapping: the answer card appears and your words show up.
- [ ] Next question: tap *Ready to answer* **while the host is still reading**. The host stops
  mid-sentence, and when you answer right away your first words are in the transcript (the mic
  reopens).
- [ ] Double-tap *Ready to answer* fast: the answer must **not** end (the second tap lands where
  *Final answer* appears).
- [ ] Tap *Different question* while the host is reading, twice in a row, then *Ready to answer*
  mid-sentence on the next one. Answer out loud: your words still show up on every later question
  (a lost cancel callback used to mute recognition for the rest of the session).
- [ ] Hold the side button for Siri while the verdict sound plays, then dismiss Siri. On the next
  question your words still show up (a paused sound used to gate the mic for good).
- [ ] Connect or disconnect AirPods mid-question. Within a few seconds your words show up again; if
  the mic can't come back, a "tap-to-advance for this turn" notice shows, and the next player's turn
  has voice again.

## 5. Edge cases

- [ ] **E2:** in iOS Settings, turn the app's microphone off → Start the show → "The show needs
  eyes and ears" → *Play without voice* works (tap *Done asking*, then *Final answer*).
- [ ] **E3:** mid-question, turn the lights down or cover the camera: a "Too dark" stamp lands on
  the camera with its fix underneath, nothing else on screen moves, and it goes when fixed. **Is
  the mustard stamp easy to spot against your room?**
- [ ] **E4:** move around a lot while answering: "No clean read" with a reason, then *Ask it again*.
- [ ] **E5:** turn on Airplane Mode, then start a turn: "The meter won't warm up" → turn Airplane
  Mode off → *Try again* works.
- [ ] **Offline mid-game:** start a turn online, then switch on Airplane Mode. **Does measuring
  carry on, or does E5 appear after a while?** (SPEC §16: does the SDK need the network after
  sign-in?)
- [ ] **Background:** mid-question, swipe home and come back within a few seconds: the question
  starts over by itself, with no Pause sheet. Stay away 20 s: the Pause sheet says "You left the
  app, so the camera stopped."; Resume restarts the question.
- [ ] **Screenshot:** mid-question and during Call it!, take a screenshot and close the preview:
  the game carries on (the question starts over; the vote keeps its time). **Does the full-screen
  preview send the app to the background on your iOS version?** (SPEC decision 72.)
- [ ] **Hand-held:** play one turn holding the phone in your hand. **How often does "Hold still"
  appear?** (SPEC §16.)
- [ ] **Frozen camera:** with the Proof Panel on, watch `cam` after the validation code through a
  turn: it should stay under 1 s. **If the preview ever freezes, note what happened just before**
  (Pause, a notification, Control Center, moving the phone) and the `cam` value. The game should
  restart the camera and the question within about 5 s (SPEC decision 64).

## 6. Network check (privacy claim)

- [ ] iOS **Settings → Privacy & Security → App Privacy Report** (turn it on first, play a game,
  then look under Sus-o-meter). **List the domains contacted.** Only Presage domains are expected.

## 7. Accessibility (quick)

- [ ] Turn on VoiceOver: in the lobby, swipe to *Solo · host asks* and double-tap. It switches.

## What to send back

1. Build result (or the first error).
2. Test connection seconds, and the code for the wrong key.
3. Mirrored preview: yes or no.
4. Pulse and transcript together: yes or no.
5. LLM insight seen after 90 s.
6. Heartbeats: the `wave` rate and conf, beats vs SDK BPM, beat vs SDK RMSSD, and whether the
   questions were scored by beats (or the reason they weren't).
7. Anything from sections 3–7 that didn't behave as described.
8. App Privacy Report domains.
