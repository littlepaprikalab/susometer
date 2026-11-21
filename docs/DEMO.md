# Demo video plan (about 2–3 minutes)

The video must show the **live Presage signals** working. Turn the Proof Panel on for part of it
(Settings → Proof panel, or long-press the lobby logo).

**Recording:** iPhone screen recording (Control Center) captures the app and the host's voice.
To also capture the table, film with a second phone, or use a split: screen recording plus a
handheld shot of the players. Good, even light on the hot seat.

**Screenshots:** on iOS 26 a screenshot opens a full-screen preview that sends the app to the
background, so a question in progress starts over (the game resumes by itself if you're back
within 15 s). To keep a question running while you take stills, turn off Settings → General →
Screen Capture → *Full-Screen Previews* first.

| # | Time | Shot | What to show / say |
|---|---|---|---|
| 1 | 0:00–0:08 | **Hook** | A Sus! verdict: buzzer, red scoreboard, applause meter full. |
| 2 | 0:08–0:20 | Lobby and consent | Add players, Party mode, Start. The consent screen: what the camera reads and that video stays on the phone. |
| 3 | 0:20–0:40 | Calibration | "Sit still", the live BPM card and the pulse waveform (SmartSpectra's arterial pressure trace), then a warm-up answered out loud. |
| 4 | 0:40–1:00 | Party question | A friend asks; the transcript appears live; "Measuring Sam" with live BPM. |
| 5 | 1:00–1:10 | Answer | The hesitation chip "Took 2.1s to start answering", pulse and blink cards moving, then **Final answer**. |
| 6 | 1:10–1:25 | Call it! → countdown → verdict | Votes, drumroll, 3-2-1, verdict with pulse/blink/pause tiles. |
| 7 | 1:25–1:40 | Solo mode | The host reads a deck question on the tomato card. |
| 8 | 1:40–1:55 | **E3 recovery** | Dim the lights: "Too dark in here", reading paused; lights back: it picks up. |
| 9 | 1:55–2:15 | **Proof Panel** | The raw SmartSpectra values: pulse + confidence, RMSSD, blink and talking flags, top expression, validation code, `tQ0…tA1` markers. |
| 10 | 2:15–2:35 | Leaderboard and replay | Awards, Best lie detector, a replay card with its pulse sparkline. |
| 11 | 2:35–2:45 | Wipe | *Wipe everything* back to an empty lobby. Close on "It reads stress, not truth." |

**Voice-over lines (optional):** "Sus-o-meter reads your pulse, blinks and face with Presage
SmartSpectra; the video never leaves the phone." · "It compares you with your own baseline, so a naturally fast
heart doesn't make you guilty." · "Shaky readings never get a score." · "It reads stress, not truth."

## The animatic (a rehearsal cut, made without a phone)

`tool/demo_video/make.sh` renders the whole demo as a film without a camera or a phone: a solo
game and a two-player party game (about three minutes), played through the **real screens** by drawn
stand-in people, with the host's voice and the game's own sounds.

```bash
tool/demo_video/make.sh
```

It writes `build/demo_video/sus-o-meter-demo.mp4` (plus `solo.mp4` and `party.mp4`) and the shot
list, `build/demo_video/shots.md`. Needs Flutter, ffmpeg and Python 3 with numpy; about six
minutes. The host's voice is [piper](https://github.com/OHF-Voice/piper1-gpl) with a British
voice (trained on public-domain LibriVox recordings), fetched on the first run; without it the
host is captions only.

**What it is and isn't.** The phone in the film shows the app's real screens, driven tap by tap
the way the UI tests drive them, and every score comes out of the real scoring code. But the
signals are made up (a scripted heart, blinks, expressions and voices; `test/film/film.dart`), so
it can't be the submission's proof that SmartSpectra works. Use it to rehearse the cut, as a
storyboard for the shoot, and as the frame real footage goes into. The film says so on screen.

**Putting real people in.** The right-hand side of the film (the "room") is cut into numbered
shots: `solo-01` … `party-14`. `shots.md` lists each one: when it is, how long it lasts, what
happens and what's said. Film any of them (landscape, 16:9, about that long), name each clip
after its shot, and render again:

```bash
tool/demo_video/make.sh --clips my_clips
```

`my_clips/party-09.mp4` then plays in place of the stand-ins for shot `party-09`: scaled to fill
the slot, cut to the shot's length (a shorter clip holds its last frame), its sound mixed in
(`--mute-clips` leaves it out). Shots without a clip keep their stand-ins, so the film can be
filled in a few clips at a time. With the picture already rendered, `--mix-only` redoes just the
clips and the sound in a few seconds.

The phone side stays the simulated app. For the submission, replace it too: screen-record the same
beats on an iPhone (the table above) and cut that in, or record the whole thing for real and use
the animatic only as the plan.

**Changing the script.** The two games are scripted in `test/demo_film_test.dart`: who says what,
which button is tapped, how each stand-in reacts (`Take.calm`, `Take.uneasy`, `Take.rattled`), and
where the film skips ahead. `FILM_DRY=1 flutter test test/demo_film_test.dart` plays it through in
half a minute without rendering and prints each question's score.
