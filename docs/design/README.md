# Design screens

The Sus-o-meter mockup (Style B, "70s game show"), copied from the project's Design canvas into
[`mocks/`](mocks/). Each screen is an iPhone frame at 390×844. `docs/SPEC.md` refers to these
screens by the names below.

The files are the canvas's HTML sources (`.dc.html`), not images. They hold the exact copy,
colors, font sizes, spacing and sample data for every screen. They need the canvas runtime
(`support.js`) to render, so read them as source rather than opening them in a browser.
[`mocks/canvas.json`](mocks/canvas.json) is the canvas index: artboard titles, positions and order.

## Screens

| File | Screen |
|---|---|
| [`Main.dc.html`](mocks/Main.dc.html) | 1 · Lobby (Party / Solo switch, gear button opens Settings) |
| [`Consent.dc.html`](mocks/Consent.dc.html) | 2 · Hot-seat consent |
| [`Calibrate.dc.html`](mocks/Calibrate.dc.html) | 3 · Calibrate baseline (sit still, then chat a bit) |
| [`Question.dc.html`](mocks/Question.dc.html) | 4a · Host: ask your question (party mode) |
| [`Question-Solo.dc.html`](mocks/Question-Solo.dc.html) | 4a · Solo mode: the host asks |
| [`Answer.dc.html`](mocks/Answer.dc.html) | 4b · Sam answers · Final answer |
| [`Verdict.dc.html`](mocks/Verdict.dc.html) | 5 · Verdict (has a `score` prop: 0–100 sets the board color and label) |
| [`Leaderboard.dc.html`](mocks/Leaderboard.dc.html) | 6 · Leaderboard |
| [`Replay.dc.html`](mocks/Replay.dc.html) | 7 · Replay |
| [`Settings.dc.html`](mocks/Settings.dc.html) | 8 · Settings · Presage API key (has a `keyState` prop: connected / missing / rejected) |
| [`Edge-HowToPlay.dc.html`](mocks/Edge-HowToPlay.dc.html) | E1 · How to play |
| [`Edge-Permissions.dc.html`](mocks/Edge-Permissions.dc.html) | E2 · Camera / mic permission off |
| [`Edge-SignalIssue.dc.html`](mocks/Edge-SignalIssue.dc.html) | E3 · Bad signal mid-question |
| [`Edge-RedoQuestion.dc.html`](mocks/Edge-RedoQuestion.dc.html) | E4 · No clean read: redo |
| [`Edge-SdkOffline.dc.html`](mocks/Edge-SdkOffline.dc.html) | E5 · SDK sign-in failed / offline |
| [`Edge-EndGame.dc.html`](mocks/Edge-EndGame.dc.html) | E6 · End the show early |

Style options for the Verdict screen (only **Style B** is built):

| File | Option |
|---|---|
| [`StyleA-Polygraph.dc.html`](mocks/StyleA-Polygraph.dc.html) | Style A · Polygraph lab report |
| [`StyleB-GameShow.dc.html`](mocks/StyleB-GameShow.dc.html) | Style B · 70s game show (chosen) |
| [`StyleC-Swiss.dc.html`](mocks/StyleC-Swiss.dc.html) | Style C · Swiss poster |

Two screens aren't mocked; SPEC.md §2 describes them: the **Countdown** and **Call it!** (room vote).

## Where the app differs from the mocks

The spec wins where the two disagree (see SPEC.md, "Decisions made during build"):

- **Room vote:** the Verdict mock has "Does the room agree?". The app moves voting to *Call it!*,
  before the reveal (SPEC.md §5.6), so the Verdict screen shows how the votes went instead.
- **Deck choice:** the Lobby mock has no Mild / Spicy picker. The app adds one, styled like the
  "Questions per turn" row, plus the one-line note that voices are transcribed on-device.
- **Saved API key:** the Settings mock shows the saved key in the field. The key never comes back
  from the Keychain (SPEC.md §6), so the field shows only a "••••1a2b" hint.
- **Error codes:** E5 shows `AUTH_FAILED`; the app shows the SDK's real code (e.g.
  `authenticationFailed`).
- **Answer screen (4b):** the mock shrinks the camera to a small LIVE thumbnail. The app keeps the
  camera card the same size and in the same place from *Ask your question!* through *Locking in
  the reading…*, because the answer is the part being measured and a jump makes people move. The
  pulse and blink cards sit over the bottom of the camera, the question is pinned inside the
  answer card, Pause stays bottom-left (the SPEC §4 state machine has Pause on 4b too), and *Final answer* fills
  the rest of the bottom row. Ask and Answer both show "Q 1 / 5" instead of dots.
- **Pulse card:** adds a small trend line for the current question, against a dashed line at the
  player's calibrated normal. The same Pulse and Blinks cards replace the Ask mock's "84 BPM" chip,
  so the camera overlay doesn't change between Ask and Answer.
- **Verdict:** adds a "Pulse through the question" chart under the three tiles (answer shaded,
  normal dashed). Replay rows use the same chart.
- **Calibrate:** the live pulse card (number and waveform) sits on the bottom of the camera, like
  the Ask/Answer cards, instead of under it, and "{name} is talking" is inside it. This gives the
  face more room on small phones.
- **E3 in the camera:** "Picks up again when it's clear" takes the live cards' place while the
  reading is paused, instead of floating over the face.
- **Leaderboard footnote:** "Scores are wiped when you leave this screen" conflicts with going on to
  the Replay. The app says scores are wiped when a new game starts or on Wipe.

## Design tokens

See `docs/SPEC.md` §3.
