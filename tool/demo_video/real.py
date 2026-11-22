#!/usr/bin/env python3
"""Lays a real iPhone screen recording into the demo film's frame.

    python3 tool/demo_video/real.py RECORDING.mp4 OUT_DIR [--steps STEPS.json]
        [--voice VOICE.m4a --voice-at SECONDS]

Writes OUT_DIR/real.mp4: the film's opening title, a "Part 1 · Played for
real" card, then the recording in the same phone frame as the animatic, with
a panel beside it saying what's happening. mix.py puts it first when it's
there (make.sh --real does both).

STEPS.json says what each stretch of the recording shows, as a list of
{"start": s, "end": s, "step": "...", "note": "..."} in the recording's own
seconds. The recording is cut where the last step ends (before Control
Center comes down to stop the recording, say). Without it, the steps of the owner's recording of 2026-11-21 are
used (a two-player party, Sam and Masa, one question each); a different
recording needs its own.

--voice adds a separate recording of the players' voices (a screen recording
doesn't capture the mic while the app is using it), starting --voice-at
seconds into the screen recording's picture. It's cleaned up (rumble, hiss,
level) and mixed with the screen recording's own sound.

The screen recording's sound is shifted to match its picture: iOS drops a
little of it whenever the app switches its audio session (the mic on, the
mic off), so after each switch it runs early. SCREEN_AUDIO_LEADS says by how
much, from when; measured for the owner's recording by when a warm-up card
or Call it! appears against when the host starts speaking. Another recording
can pass its own with --audio-leads, or none.

Needs ffmpeg, numpy and Pillow.
"""

import argparse
import json
import subprocess
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "assets" / "fonts"
W, H = 1920, 1080
FPS = 30

# The animatic's colours and layout (test/film/stage.dart).
INK = (0x1C, 0x0E, 0x07)
APP_INK = (0x2A, 0x16, 0x0C)
CREAM = (0xFF, 0xF4, 0xDF)
MUSTARD = (0xF2, 0xB3, 0x3D)
TOMATO = (0xD9, 0x41, 0x2B)
TEAL = (0x1F, 0x6F, 0x78)
BULB = (0xFF, 0xE9, 0xA8)
MUTED = (0xCD, 0xB8, 0x94)
BEZEL = (0x0D, 0x07, 0x05)
PHONE = (70, 24, 492, 1032)  # left, top, width, height
BEZEL_W = 14
ROOM = (640, 128, 1216, 684)

# The owner's recording: a two-player party, one question each.
DEFAULT_STEPS = [
    (0, 7.5, "Set up", "Two players, Sam and Masa, on one iPhone. Party mode, one question each."),
    (7.5, 10, "How to play", "The house rule: it reads stress, not truth."),
    (10, 34, "Calibrate Sam · sit still",
     "The front camera finds Sam’s face. SmartSpectra’s pulse comes in live on the card, "
     "and the sit-still ends once it’s steady."),
    (34, 54, "Calibrate Sam · warm-ups",
     "Three easy questions, answered out loud: Sam’s normal blinks, expressions and answer "
     "speed. The #tag is SmartSpectra’s top expression, live."),
    (54, 61, "Question 1 · Masa asks",
     "Stuck for a question? “Suggest one” puts a deck question on the card for the asker "
     "to read out."),
    (61, 74, "Question 1 · Sam answers",
     "Speech becomes text on the phone. Sam took 7 seconds to start answering: the pause "
     "counts toward the score."),
    (74, 80, "Call it!", "Masa votes Legit or Sus before the meter shows its hand."),
    (80, 86.5, "The verdict · 28, Legit",
     "Scored against Sam’s own warm-ups: pulse, blinks, expressions and the pause."),
    (86.5, 106, "Calibrate Masa · sit still",
     "Then they swap. A fresh baseline for Masa: everyone is compared with their own normal."),
    (106, 130, "Calibrate Masa · warm-ups",
     "Masa chats through the warm-ups. Live pulse and blink rate on the card."),
    (130, 154, "Question 1 · Sam asks",
     "“Have you ever pretended your phone was dead to avoid a text?”"),
    (154, 166, "Question 1 · Masa answers", "“No, never.” Then a few seconds to lock in the reading."),
    (166, 170, "Call it!", "Sam calls it."),
    (170, 174, "The verdict · 43, Hmm…", "Not quite Legit. The room can argue about it."),
    # At 179 s Control Center comes down to stop the recording.
    (174, 178.8, "And the winners are…",
     "Best poker face: Sam. Most sus: Masa. Nothing is saved; a new game wipes it."),
]


# The owner's recording: (from this second of its sound, it runs this many
# seconds ahead of the picture). The cuts fall in silence.
SCREEN_AUDIO_LEADS = [(0, 0.19), (84, 0.49), (172, 0.62)]

# The owner's voice memo starts this far into the recording's picture: 28.97 s
# into its sound by cross-correlation (the memo hears the phone's host), plus
# that sound's 0.19 s lead there, plus 0.05 s so the host the memo heard lands
# on the host in the screen recording.
DEFAULT_VOICE_AT = 29.25

RATE = 48000

# Rumble and hiss out, the quiet room gated, the voice brought up to sit with
# the host.
VOICE_FILTER = (
    "highpass=f=90,lowpass=f=9000,afftdn=nf=-50:nr=15,volume=18dB,"
    "agate=threshold=0.045:ratio=6:range=0.05:attack=8:release=250,"
    "acompressor=threshold=-24dB:ratio=3:attack=5:release=150:makeup=4dB,"
    "alimiter=limit=0.9"
)


# Text the app got wrong in the owner's recording, painted over in its own
# font and colours, frame-exact. Masa answered "No, never" before Sam tapped
# Done asking, so the app took the answer for the question. Each patch: the
# seconds it's on screen (halfway between frames, from the frames' own
# timestamps: the recording's frame rate varies), the wrong text's ink box,
# and what the app shows
# when it hears nothing (question_screens.dart, result_screens.dart). Sizes,
# colours and origins measured from the recording (3 px a point).
APP_CREAM = (253, 240, 216)
APP_BROWN = (0x8A, 0x4B, 0x1C)
PATCHES = [
    # Sam's asking card: "Heard: No" / "Heard: No, never".
    dict(t0=152.2255, t1=153.205, old=(114, 943, 441, 977), origin=(114, 935),
         text="Read it out, or ask your own.", font="WorkSans-SemiBold.ttf", size=40.0,
         color=APP_BROWN),
    # Masa's answer screen: Q: "No, never".
    dict(t0=153.205, t1=165.225, old=(113, 499, 414, 537), origin=(113, 490),
         text="Q: (asked out loud)", font="WorkSans-SemiBold.ttf", size=43.0,
         color=APP_BROWN),
    # The verdict.
    dict(t0=170.71, t1=174.6285, old=(107, 417, 453, 460), origin=(107, 406),
         text="Q: “Question 1”", font="WorkSans-Bold.ttf", size=49.0, color=APP_INK),
    # The winners: Biggest spike.
    dict(t0=174.6285, t1=10_000, old=(414, 1018, 676, 1056), origin=(414, 1006),
         text="“Question 1”", font="WorkSans-Bold.ttf", size=45.7, color=APP_INK),
]


def patch_png(path, patch, size):
    """One patch at the recording's size: the old text covered, the new drawn."""
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = font(patch["font"], patch["size"])
    ox, oy = patch["origin"]
    nb = f.getbbox(patch["text"])
    x0, y0, x1, y1 = patch["old"]
    cover = (min(x0, ox + nb[0]) - 6, min(y0, oy + nb[1]) - 6,
             max(x1, ox + nb[2]) + 6, max(y1, oy + nb[3]) + 6)
    d.rectangle(cover, fill=APP_CREAM + (255,))
    d.text((ox, oy), patch["text"], font=f, fill=patch["color"] + (255,))
    img.save(path)


def decode(path, channels, af=None):
    """A sound file as float samples at RATE, shape (n, channels)."""
    cmd = ["ffmpeg", "-loglevel", "error", "-i", str(path), "-vn"]
    if af:
        cmd += ["-af", af]
    cmd += ["-f", "f32le", "-ac", str(channels), "-ar", str(RATE), "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, channels)


def soundtrack(recording, length, path, leads, voice=None, voice_at=0.0):
    """The recording's sound put back in step with its picture, plus the voice."""
    screen = decode(recording, 2)
    n = int(length * RATE)
    track = np.zeros((n, 2), dtype=np.float32)
    bounds = [a for a, _ in leads] + [len(screen) / RATE]
    for (start, lead), end in zip(leads or [(0, 0.0)], bounds[1:] or [len(screen) / RATE]):
        seg = screen[int(start * RATE):int(end * RATE)] * 10 ** (-2 / 20)
        at = int((start + lead) * RATE)
        stop = min(n, at + len(seg))
        if stop > at:
            track[at:stop] += seg[: stop - at]
    if voice is not None:
        v = decode(voice, 1, VOICE_FILTER)[:, 0]
        at = int(voice_at * RATE)
        skip = max(0, -at)
        at = max(0, at)
        v = v[skip:]
        stop = min(n, at + len(v))
        if stop > at:
            placed = np.zeros(n, dtype=np.float32)
            placed[at:stop] = v[: stop - at]
            # The voice recording hears the phone's speaker too: muted while
            # the game makes a sound, so the host and the sounds come only
            # from the screen recording and don't echo.
            track += (placed * game_quiet(track))[:, None]
    fade = int(0.4 * RATE)
    track[-fade:] *= np.linspace(1, 0, fade, dtype=np.float32)[:, None]
    peak = float(np.abs(track).max()) or 1.0
    if peak > 0.95:
        track *= 0.95 / peak
    with wave.open(str(path), "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((track * 32767).astype("<i2").tobytes())


def game_quiet(track, before=0.08, after=0.3, ramp=0.03):
    """Per sample, 1 where the game is silent and 0 around its sounds."""
    hop = RATE // 100
    m = np.abs(track).max(1)
    frames = len(m) // hop
    env = m[: frames * hop].reshape(frames, hop).max(1)
    loud = env > 10 ** (-50 / 20)
    pre, post = int(before * 100), int(after * 100)
    idx = np.flatnonzero(loud)
    busy = np.zeros(frames, dtype=bool)
    for i in idx:
        busy[max(0, i - pre):i + post + 1] = True
    gain = np.where(busy, 0.0, 1.0).astype(np.float32)
    k = max(1, int(ramp * 100))
    gain = np.convolve(gain, np.ones(k) / k, mode="same").astype(np.float32)
    out = np.repeat(gain, hop)
    return np.pad(out, (0, len(m) - len(out)), constant_values=out[-1] if len(out) else 1.0)


def font(name, size):
    return ImageFont.truetype(str(FONTS / name), size)


DISPLAY = "BowlbyOneSC-Regular.ttf"
BODY = "WorkSans-SemiBold.ttf"
BOLD = "WorkSans-Bold.ttf"


def run(*args):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *map(str, args)], check=True)


def video_size(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=width,height",
         "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, check=True,
    )
    w, h = out.stdout.strip().split(",")[:2]
    return int(w), int(h)


def duration(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, check=True,
    )
    return float(out.stdout.strip())


def wrap(draw, text, fnt, width):
    """Lines of [text] that fit [width] pixels."""
    words, lines, line = text.split(), [], ""
    for w in words:
        trial = f"{line} {w}".strip()
        if draw.textlength(trial, font=fnt) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines


def bulbs(draw, cx, y, n=14, r=10, gap=52):
    x0 = cx - (n - 1) * gap / 2
    for i in range(n):
        x = x0 + i * gap
        draw.ellipse((x - r, y - r, x + r, y + r), fill=BULB, outline=APP_INK, width=3)


def title_card(path, title, lines, kicker=None):
    """The animatic's TitleCard: a marquee on mustard."""
    img = Image.new("RGB", (W, H), MUSTARD)
    d = ImageDraw.Draw(img)
    tf, kf, lf = font(DISPLAY, 120), font(DISPLAY, 40), font(BODY, 40)
    tw = d.textlength(title, font=tf)
    box_w = max(tw + 140, 14 * 52 + 60)
    box_h = 26 + 20 + 18 + 126 + 18 + 20 + 26
    kick_h = 66 if kicker else 0
    total = kick_h + box_h + 52 + 50 * len(lines)
    top = (H - total) / 2
    if kicker:
        d.text((W / 2, top), kicker, font=kf, fill=APP_INK, anchor="mt")
    bx0, by0 = (W - box_w) / 2, top + kick_h
    d.rounded_rectangle((bx0, by0 + 12, bx0 + box_w, by0 + box_h + 12), 44, fill=APP_INK)
    d.rounded_rectangle((bx0, by0, bx0 + box_w, by0 + box_h), 44, fill=TOMATO, outline=APP_INK, width=6)
    bulbs(d, W / 2, by0 + 36)
    d.text((W / 2, by0 + box_h / 2 + 4), title, font=tf, fill=CREAM, anchor="mm")
    bulbs(d, W / 2, by0 + box_h - 36)
    y = by0 + box_h + 52
    for line in lines:
        d.text((W / 2, y), line, font=lf, fill=APP_INK, anchor="mt")
        y += 50
    img.save(path)


def phone_frame(path):
    """Everything but the screen: stage ink, the bezel, and rounded corners."""
    img = Image.new("RGBA", (W, H), INK + (255,))
    d = ImageDraw.Draw(img)
    x, y, w, h = PHONE
    d.rounded_rectangle((x, y, x + w, y + h), 58, fill=BEZEL, outline=(0x5B, 0x46, 0x36), width=2)
    sx, sy = x + BEZEL_W, y + BEZEL_W
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (sx, sy, sx + w - 2 * BEZEL_W, sy + h - 2 * BEZEL_W), 46, fill=255
    )
    img.putalpha(Image.eval(mask, lambda v: 255 - v))
    img.save(path)


def step_panel(path, step, note):
    """The right-hand side for one step (transparent elsewhere)."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rx, ry, rw, rh = ROOM
    # Header: chapter chip and step.
    chip_f, step_f = font(DISPLAY, 26), font(DISPLAY, 32)
    chip = "PLAYED FOR REAL"
    cw = d.textlength(chip, font=chip_f) + 36
    d.rounded_rectangle((rx, 34, rx + cw, 94), 14, fill=TOMATO, outline=CREAM, width=3)
    d.text((rx + cw / 2, 65), chip, font=chip_f, fill=CREAM, anchor="mm")
    d.text((rx + cw + 20, 65), "SAM & MASA · ONE IPHONE", font=step_f, fill=BULB, anchor="lm")
    # The panel where the animatic's room is.
    d.rounded_rectangle((rx, ry, rx + rw, ry + rh), 26, fill=(0x1B, 0x4A, 0x51))
    stripes = [MUSTARD, TOMATO, CREAM]
    for i, c in enumerate(stripes):
        y0 = ry + 318 + i * 22
        d.rectangle((rx, y0, rx + rw, y0 + 22), fill=tuple(int(v * 0.5 + 0x1B * 0.5) for v in c))
    # Badge: what this footage is.
    badge_f = font(BOLD, 22)
    badge = "iPhone screen recording · uncut · live Presage SmartSpectra signals"
    bw = d.textlength(badge, font=badge_f) + 64
    d.rounded_rectangle((rx + 24, ry + 24, rx + 24 + bw, ry + 70), 12, fill=APP_INK)
    d.ellipse((rx + 44, ry + 39, rx + 60, ry + 55), fill=TOMATO)
    d.text((rx + 72, ry + 47), badge, font=badge_f, fill=BULB, anchor="lm")
    # The step, big, and what's going on.
    big_f, note_f = font(DISPLAY, 64), font(BODY, 36)
    card_x0, card_x1 = rx + 60, rx + rw - 60
    big_lines = wrap(d, step.upper(), big_f, card_x1 - card_x0 - 80)
    note_lines = wrap(d, note, note_f, card_x1 - card_x0 - 80)
    card_h = 50 + 72 * len(big_lines) + 24 + 48 * len(note_lines) + 50
    card_y0 = ry + rh / 2 - card_h / 2 + 30
    d.rounded_rectangle((card_x0, card_y0 + 10, card_x1, card_y0 + card_h + 10), 28, fill=APP_INK)
    d.rounded_rectangle((card_x0, card_y0, card_x1, card_y0 + card_h), 28, fill=CREAM, outline=APP_INK, width=5)
    y = card_y0 + 50
    for line in big_lines:
        d.text((card_x0 + 40, y), line, font=big_f, fill=APP_INK)
        y += 72
    y += 24
    for line in note_lines:
        d.text((card_x0 + 40, y), line, font=note_f, fill=APP_INK)
        y += 48
    # Under the panel, as in the animatic.
    d.text((rx, ry + rh + 30), "It reads stress, not truth. For fun only.",
           font=font(BODY, 30), fill=MUTED)
    d.text((rx, H - 22), "Real game · real person · the phone shows a screen recording of the app",
           font=font("WorkSans-Medium.ttf", 17), fill=MUTED + (190,), anchor="ls")
    img.save(path)


def build(recording, out, steps, leads=SCREEN_AUDIO_LEADS, voice=None, voice_at=DEFAULT_VOICE_AT,
          patches=PATCHES):
    work = out / "real"
    work.mkdir(parents=True, exist_ok=True)
    length = min(duration(recording), max(end for _, end, _, _ in steps))
    sound = work / "sound.wav"
    soundtrack(recording, length, sound, leads, voice, voice_at)

    title_card(work / "card-title.png", "Sus-o-meter",
               ["The party game that reads your pulse.", "Not your mind."])
    title_card(work / "card-part1.png", "Played for real",
               ["Two players, one iPhone, live Presage SmartSpectra signals.",
                "A screen recording, uncut."], kicker="PART 1")
    phone_frame(work / "frame.png")

    listing = []
    for i, (start, end, step, note) in enumerate(steps):
        start, end = max(0.0, start), min(end, length)
        if end <= start:
            continue
        png = work / f"step-{i:02d}.png"
        step_panel(png, step, note)
        listing.append(f"file '{png.name}'\nduration {end - start:.3f}\n")
    # The concat demuxer needs the last file again to honour its duration.
    listing.append(listing[-1].split("\n")[0] + "\n")
    (work / "steps.txt").write_text("".join(listing))

    x, y, w, h = PHONE
    sw, sh = w - 2 * BEZEL_W, h - 2 * BEZEL_W
    rec_size = video_size(recording)
    # In RGB first: the recording is full-range video, and patches blended
    # straight onto it come out a shade darker than the card around them.
    patch_inputs, patch_graph, cur = [], "[0:v]format=rgba[src];", "[src]"
    for i, p in enumerate(patches):
        png = work / f"patch-{i}.png"
        patch_png(png, p, rec_size)
        patch_inputs += ["-loop", "1", "-i", png]
        patch_graph += (f"{cur}[{4 + i}:v]overlay=0:0:shortest=1:"
                        f"enable='between(t,{p['t0']:.3f},{min(p['t1'], length + 1):.3f})'[p{i}];")
        cur = f"[p{i}]"
    body = work / "body.mp4"
    run(
        "-i", recording,
        "-f", "concat", "-safe", "0", "-i", work / "steps.txt",
        "-loop", "1", "-i", work / "frame.png",
        "-i", sound,
        *patch_inputs,
        "-filter_complex",
        f"color=c=0x{INK[0]:02x}{INK[1]:02x}{INK[2]:02x}:s={W}x{H}:r={FPS}:d={length:.3f}[bg];"
        + patch_graph +
        f"{cur}fps={FPS},scale={sw}:-2,crop={sw}:{sh}:0:(ih-{sh})/2,setsar=1[rec];"
        f"[bg][rec]overlay={x + BEZEL_W}:{y + BEZEL_W}:shortest=1[a];"
        f"[2:v]format=rgba[frame];[a][frame]overlay=0:0:shortest=1[b];"
        f"[1:v]fps={FPS},format=rgba[steps];"
        f"[b][steps]overlay=0:0:eof_action=repeat,format=yuv420p[v]",
        "-map", "[v]", "-map", "3:a", "-t", f"{length:.3f}",
        "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "160k", "-ac", "2", "-ar", "48000",
        body,
    )

    final = out / "real.mp4"
    run(
        "-loop", "1", "-t", "2.6", "-framerate", FPS, "-i", work / "card-title.png",
        "-loop", "1", "-t", "2.4", "-framerate", FPS, "-i", work / "card-part1.png",
        "-i", body,
        "-f", "lavfi", "-t", "5", "-i", "anullsrc=r=48000:cl=stereo",
        "-filter_complex",
        "[0:v]format=yuv420p,setsar=1[c0];[1:v]format=yuv420p,setsar=1[c1];"
        "[3:a]atrim=0:2.6,asetpts=PTS-STARTPTS[s0];[3:a]atrim=0:2.4,asetpts=PTS-STARTPTS[s1];"
        "[c0][s0][c1][s1][2:v][2:a]concat=n=3:v=1:a=1[v][a]",
        "-map", "[v]", "-map", "[a]",
        "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
        "-r", FPS, "-video_track_timescale", "15360",
        "-c:a", "aac", "-b:a", "160k", "-ac", "2", "-ar", "48000",
        "-movflags", "+faststart", final,
    )
    return final


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("recording", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--steps", type=Path, help="JSON list of {start, end, step, note}")
    ap.add_argument("--voice", type=Path, help="a recording of the players' voices")
    ap.add_argument("--voice-at", type=float, default=DEFAULT_VOICE_AT,
                    help="where the voice recording starts in the picture, in seconds")
    ap.add_argument("--audio-leads", type=Path,
                    help="JSON [[from_s, lead_s], ...] for the screen recording's sound; [] for none")
    ap.add_argument("--no-patches", action="store_true",
                    help="leave the owner's recording's text fixes out (another recording)")
    args = ap.parse_args()
    steps = DEFAULT_STEPS
    if args.steps:
        steps = [(s["start"], s["end"], s["step"], s.get("note", ""))
                 for s in json.loads(args.steps.read_text())]
    leads = SCREEN_AUDIO_LEADS
    if args.audio_leads:
        leads = [tuple(x) for x in json.loads(args.audio_leads.read_text())]
    final = build(args.recording, args.out, steps, leads, args.voice, args.voice_at,
                  [] if args.no_patches else PATCHES)
    print(f"{final}  ({duration(final):.1f} s)")


if __name__ == "__main__":
    main()
