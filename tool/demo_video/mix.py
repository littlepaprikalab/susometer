#!/usr/bin/env python3
"""Finishes the demo film that test/demo_film_test.dart rendered.

For each part (solo, party) it lays the soundtrack (host voice, sound effects)
under the picture, swaps real clips in for the stand-in "room" shots, joins the
parts, and writes the shot list:

    python3 tool/demo_video/mix.py build/demo_video [--clips DIR]

A clip replaces the shot it's named after: DIR/party-04.mp4 goes in the room
picture for shot party-04 (see shots.md for what each shot shows, when and for
how long). It's scaled to fill the 16:9 slot and cut to the shot's length; a
shorter clip holds its last frame. Its sound is mixed in unless --mute-clips.

Needs ffmpeg and numpy.
"""

import argparse
import json
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

RATE = 48000
PARTS = ["solo", "party"]
CLIP_TYPES = [".mp4", ".mov", ".m4v", ".webm", ".mkv"]


def run(*args):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *map(str, args)], check=True)


def decode(path):
    """A sound file as mono float samples at RATE; None if it has no audio."""
    out = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", str(path), "-vn",
         "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"],
        capture_output=True,
    )
    if out.returncode != 0 or not out.stdout:
        return None
    return np.frombuffer(out.stdout, dtype=np.float32)


def place(track, samples, start, gain=1.0, cut=None):
    """Adds [samples] to [track] at [start] seconds, cut short after [cut]."""
    if cut is not None:
        samples = samples[: max(0, int(cut * RATE))].copy()
        fade = min(len(samples), int(0.08 * RATE))
        if fade:
            samples[-fade:] *= np.linspace(1, 0, fade, dtype=np.float32)
    at = int(start * RATE)
    end = min(len(track), at + len(samples))
    if end > at:
        track[at:end] += gain * samples[: end - at]


def find_clip(clips, shot_id):
    if clips is None:
        return None
    for ext in CLIP_TYPES:
        path = clips / f"{shot_id}{ext}"
        if path.exists():
            return path
    return None


def stamp(seconds):
    return f"{int(seconds // 60)}:{seconds % 60:04.1f}"


def finish_part(out, name, clips, mute_clips):
    events = json.loads((out / f"{name}.events.json").read_text())
    duration = events["duration"]
    track = np.zeros(int(duration * RATE) + RATE // 2, dtype=np.float32)
    cache = {}
    for e in events["audio"]:
        if e["file"] not in cache:
            cache[e["file"]] = decode(e["file"])
        samples = cache[e["file"]]
        if samples is not None:
            place(track, samples, e["start"], e.get("gain", 1.0), e.get("cut"))

    # Real clips over the stand-ins.
    x, y, w, h = (int(v) for v in events["room"])
    inputs = ["-i", out / f"{name}.video.mp4"]
    graph = []
    last = "0:v"
    used = []
    for shot in events["shots"]:
        clip = find_clip(clips, shot["id"])
        if clip is None:
            continue
        start, length = shot["start"], shot["end"] - shot["start"]
        n = len(used) + 1
        inputs += ["-i", clip]
        graph.append(
            f"[{n}:v]fps={events['fps']},"
            f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},"
            f"tpad=stop_mode=clone:stop_duration={length:.3f},"
            f"trim=0:{length:.3f},setpts=PTS-STARTPTS+{start:.3f}/TB[c{n}];"
            f"[{last}][c{n}]overlay={x}:{y}:eof_action=pass:"
            f"enable='between(t,{start:.3f},{shot['end']:.3f})'[v{n}]"
        )
        last = f"v{n}"
        used.append(shot["id"])
        if not mute_clips:
            samples = decode(clip)
            if samples is not None:
                place(track, samples, start, cut=length)

    peak = float(np.abs(track).max()) if len(track) else 0.0
    if peak > 0.95:
        track *= 0.95 / peak
    wav = out / f"{name}.audio.wav"
    with wave.open(str(wav), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((track * 32767).astype("<i2").tobytes())

    final = out / f"{name}.mp4"
    video = (
        ["-filter_complex", ";".join(graph), "-map", f"[{last}]",
         "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p"]
        if graph
        else ["-map", "0:v", "-c:v", "copy"]
    )
    run(*inputs, "-i", wav, *video, "-map", f"{len(used) + 1}:a",
        "-c:a", "aac", "-b:a", "160k", "-ac", "2", "-t", f"{duration:.3f}",
        "-movflags", "+faststart", final)
    return events, used


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out", type=Path, help="where the film was rendered")
    ap.add_argument("--clips", type=Path, help="real clips, named <shot id>.mp4")
    ap.add_argument("--mute-clips", action="store_true", help="leave the clips' sound out")
    args = ap.parse_args()
    out = args.out
    parts = [p for p in PARTS if (out / f"{p}.events.json").exists()]
    if not parts:
        sys.exit(f"Nothing rendered in {out}: run tool/demo_video/make.sh first.")

    rows = []
    offset = 0.0
    replaced = []
    for name in parts:
        events, used = finish_part(out, name, args.clips, args.mute_clips)
        replaced += used
        for shot in events["shots"]:
            rows.append({
                **shot,
                "part": name,
                "start": shot["start"] + offset,
                "end": shot["end"] + offset,
                "in_part": shot["start"],
                "clip": shot["id"] in used,
            })
        offset += events["duration"]

    listing = out / "parts.txt"
    listing.write_text("".join(f"file '{p}.mp4'\n" for p in parts))
    whole = out / "sus-o-meter-demo.mp4"
    run("-f", "concat", "-safe", "0", "-i", listing, "-c", "copy",
        "-movflags", "+faststart", whole)

    (out / "shots.json").write_text(json.dumps(rows, indent=1))
    lines = [
        "# Shot list",
        "",
        "Each row is one stretch of the room picture (the right-hand side of the",
        "film), drawn with stand-ins. To replace one with real people, film that",
        "moment (landscape, 16:9, about the length given), save it as",
        "`<shot>.mp4` in one folder and run",
        "`tool/demo_video/make.sh --clips <folder>`.",
        "",
        "| Shot | In the film | Length | What happens | What's said |",
        "|---|---|---|---|---|",
    ]
    for r in rows:
        said = "<br>".join(r["lines"]) or " "
        mark = " (clip)" if r["clip"] else ""
        lines.append(
            f"| `{r['id']}`{mark} | {stamp(r['start'])}–{stamp(r['end'])} "
            f"| {r['end'] - r['start']:.1f} s | {r['what']} | {said} |"
        )
    (out / "shots.md").write_text("\n".join(lines) + "\n")

    print(f"{whole}  ({stamp(offset)})")
    for name in parts:
        print(f"{out / (name + '.mp4')}")
    print(f"{out / 'shots.md'}  ({len(rows)} shots, {len(replaced)} with real clips)")


if __name__ == "__main__":
    main()
