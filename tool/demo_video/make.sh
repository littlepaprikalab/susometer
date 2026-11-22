#!/usr/bin/env bash
# Renders the demo film: a solo game and a party game played through the real
# screens by stand-in people (test/demo_film_test.dart), with the host's voice
# and the game's sounds.
#
#   tool/demo_video/make.sh                    # build/demo_video/sus-o-meter-demo.mp4
#   tool/demo_video/make.sh --clips my_clips   # real clips over the stand-ins
#   tool/demo_video/make.sh --clips my_clips --mix-only   # picture already rendered
#   tool/demo_video/make.sh --real game.mp4    # a real screen recording as part 1
#   tool/demo_video/make.sh --real game.mp4 --voice voices.m4a   # with the players' voices
#
# Clips are named after the shot they replace (my_clips/party-04.mp4); the shot
# list is build/demo_video/shots.md. Needs flutter, ffmpeg, python3 with numpy
# (and Pillow for --real).
#
# --real puts a real iPhone screen recording first (real.py lays it in the
# film's phone frame, with a panel saying what each step is), then the solo
# animatic as part 2 (the real game takes the party animatic's place). Its steps are described in real.py; a different
# recording needs --steps steps.json.
#
# The host's voice is piper (https://github.com/OHF-Voice/piper1-gpl) with a
# British voice, installed into the output folder on the first run. Without
# it (no network, or FILM_PIPER= set empty) the host is captions only. To use
# another voice: FILM_PIPER="piper -m /path/to/voice.onnx".
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=build/demo_video
RENDER=1
MIX_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --mix-only) RENDER=0; shift ;;
    --clips) MIX_ARGS+=(--clips "$2"); shift 2 ;;
    --mute-clips) MIX_ARGS+=(--mute-clips); shift ;;
    --real) MIX_ARGS+=(--real "$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"); export FILM_WITH_REAL=1; shift 2 ;;
    --steps) MIX_ARGS+=(--steps "$2"); shift 2 ;;
    --voice) MIX_ARGS+=(--voice "$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"); shift 2 ;;
    --voice-at) MIX_ARGS+=(--voice-at "$2"); shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

if [ "$RENDER" = 1 ]; then
  if [ -z "${FILM_PIPER+set}" ]; then
    TTS="$OUT/tts"
    VOICE=en_GB-cori-high
    VOICE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/cori/high"
    if [ ! -x "$TTS/bin/piper" ]; then
      python3 -m venv "$TTS" && "$TTS/bin/pip" install -q piper-tts || true
    fi
    for f in "$VOICE.onnx" "$VOICE.onnx.json"; do
      [ -s "$TTS/$f" ] || curl -fsSL --retry 3 -o "$TTS/$f" "$VOICE_URL/$f" || rm -f "$TTS/$f"
    done
    if [ -x "$TTS/bin/piper" ] && [ -s "$TTS/$VOICE.onnx" ] && [ -s "$TTS/$VOICE.onnx.json" ]; then
      FILM_PIPER="$TTS/bin/piper -m $TTS/$VOICE.onnx"
    else
      echo "No host voice (piper or its voice couldn't be installed): captions only." >&2
      FILM_PIPER=
    fi
  fi
  export FILM_PIPER
  if [ "${FILM_WITH_REAL:-}" = 1 ]; then
    FILM_OUT="$OUT" flutter test test/demo_film_test.dart --plain-name "a solo game"
  else
    FILM_OUT="$OUT" flutter test test/demo_film_test.dart
  fi
fi

python3 tool/demo_video/mix.py "$OUT" "${MIX_ARGS[@]}"
