#!/usr/bin/env bash
# Makes packages/demo/build/readme_demo.mp4, the video in README.md: records
# the demo's flyover in its recording mode on macOS and adds a title card. It
# needs no input while it runs. CONTRIBUTING.md describes the one-time setup
# and how to upload the video to GitHub; the script doesn't upload it.
#
#   packages/demo/tool/record_readme.sh              makes the video
#   packages/demo/tool/record_readme.sh card <png>   writes only the title card
#
# Design: openspec/changes/readme-demo-recording/design.md, D148 to D151.
set -euo pipefail

# The clip length in seconds; the demo's warm-up pass covers 1 s more.
readonly CLIP_SECONDS=20
readonly FPS=60
readonly WIDTH=1280
readonly HEIGHT=720
# GitHub's limit for a video attachment on its free plan.
readonly MAX_BYTES=10000000
# H.264 CRF values to try, in order, until the video is at most MAX_BYTES.
readonly CRFS=(24 25 26)

readonly TITLE="Mapigrade demo"
readonly SUBTITLE="Flyover of the Tour de France Femmes avec Zwift 2026, stage 9, Nice"

TOOL_DIR=$(cd "$(dirname "$0")" && pwd)
readonly TOOL_DIR
DEMO_DIR=$(cd "$TOOL_DIR/.." && pwd)
readonly DEMO_DIR
REPO_DIR=$(cd "$TOOL_DIR/../../.." && pwd)
readonly REPO_DIR
readonly OUTPUT="$DEMO_DIR/build/readme_demo.mp4"
readonly LOGO="$REPO_DIR/assets/mapigrade.svg"
readonly DEMO_BINARY="$DEMO_DIR/build/macos/Build/Products/Release/mapigrade_demo.app/Contents/MacOS/mapigrade_demo"

work=""
helper_pid=""

fail() {
  echo "record_readme: $*" >&2
  exit 1
}

cleanup() {
  # The helper stops the demo when it is stopped.
  if [[ -n "$helper_pid" ]] && kill -0 "$helper_pid" 2>/dev/null; then
    kill "$helper_pid" 2>/dev/null || true
    wait "$helper_pid" 2>/dev/null || true
  fi
  if [[ -n "$work" ]]; then rm -rf "$work"; fi
}

check_tools() {
  local missing=()
  command -v flutter >/dev/null || missing+=("flutter: install Flutter as CONTRIBUTING.md describes")
  command -v swiftc >/dev/null || missing+=("swiftc: xcode-select --install")
  command -v magick >/dev/null || missing+=("magick: brew install imagemagick")
  command -v rsvg-convert >/dev/null || missing+=("rsvg-convert: brew install librsvg")
  if ! command -v ffmpeg >/dev/null; then
    missing+=("ffmpeg: brew install ffmpeg")
  elif ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libx264; then
    missing+=("ffmpeg with the libx264 encoder: brew reinstall ffmpeg")
  fi
  if ((${#missing[@]})); then
    echo "record_readme: these tools are missing; install them and run the script again:" >&2
    printf '  %s\n' "${missing[@]}" >&2
    exit 1
  fi
}

# Compiles the capture helper into the work directory, and checks that the
# app that runs this script has Screen Recording permission.
check_permission() {
  swiftc -swift-version 5 -O -o "$work/capture_window" "$TOOL_DIR/capture_window.swift"
  local status=0
  "$work/capture_window" check || status=$?
  if ((status == 2)); then
    fail "grant Screen Recording permission to ${__CFBundleIdentifier:-the app that runs this script}, as the message above describes"
  elif ((status != 0)); then
    fail "the capture helper's permission check failed with status $status"
  fi
}

# Writes the title card to $1: a transparent PNG of WIDTH x HEIGHT.
make_card() {
  local out=$1 dir
  dir=$(mktemp -d)
  rsvg-convert -h 130 "$LOGO" -o "$dir/logo.png"
  magick -size "${WIDTH}x${HEIGHT}" xc:none \
    -fill "rgba(244,242,246,0.97)" -draw "roundrectangle 180,262 1100,574 24,24" \
    \( +clone -background black -shadow 35x12+0+6 \) +swap \
    -background none -layers merge +repage \
    \( "$dir/logo.png" \) -gravity north -geometry +0+284 -composite \
    -fill "#1b1b21" -font Helvetica-Neue-Bold -pointsize 56 \
    -annotate +0+426 "$TITLE" \
    -fill "#46464f" -font Helvetica-Neue -pointsize 28 \
    -annotate +0+510 "$SUBTITLE" \
    -crop "${WIDTH}x${HEIGHT}+0+0" +repage \
    "$out"
  rm -rf "$dir"
}

# Encodes the capture $1 with the card $2 into the MP4 $3 at CRF $4: the
# capture at FPS, scaled to WIDTH x HEIGHT, with the card over it.
encode() {
  local capture=$1 card=$2 out=$3 crf=$4
  # The capture is BT.709. The card goes over the scaled map, so that its
  # text is rendered at the video's size; it is fully shown until 2.5 s and
  # fades out by 3.5 s.
  ffmpeg -hide_banner -loglevel error -stats -y \
    -i "$capture" -loop 1 -i "$card" \
    -filter_complex "[0:v]fps=$FPS,scale=$WIDTH:$HEIGHT:flags=lanczos+accurate_rnd+full_chroma_int:in_color_matrix=bt709:in_range=tv:out_color_matrix=bt709:out_range=tv,format=yuv420p[map];[1:v]fps=$FPS,format=rgba,fade=t=out:st=2.5:d=1:alpha=1[card];[map][card]overlay=shortest=1:format=yuv420,format=yuv420p" \
    -t "$CLIP_SECONDS" -c:v libx264 -preset slow -crf "$crf" -profile:v high \
    -pix_fmt yuv420p -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
    -movflags +faststart -an "$out"
}

main() {
  check_tools
  work=$(mktemp -d)
  trap cleanup EXIT
  trap 'exit 130' INT TERM
  check_permission

  echo "record_readme: building the demo"
  (cd "$DEMO_DIR" && flutter build macos --release)
  echo "record_readme: recording: a warm-up pass of $((CLIP_SECONDS + 1)) s, then $CLIP_SECONDS s"
  "$work/capture_window" record "$DEMO_BINARY" "$CLIP_SECONDS" "$work/capture.mov" &
  helper_pid=$!
  wait "$helper_pid"
  helper_pid=""

  make_card "$work/card.png"
  local crf size sizes=""
  for crf in "${CRFS[@]}"; do
    echo "record_readme: encoding $CLIP_SECONDS s at $FPS fps, CRF $crf"
    encode "$work/capture.mov" "$work/card.png" "$work/readme_demo.mp4" "$crf"
    size=$(stat -f %z "$work/readme_demo.mp4")
    echo "record_readme: CRF $crf: $size bytes"
    sizes+="${sizes:+, }CRF $crf: $size bytes"
    if ((size <= MAX_BYTES)); then
      mkdir -p "$(dirname "$OUTPUT")"
      mv "$work/readme_demo.mp4" "$OUTPUT"
      echo "record_readme: wrote $OUTPUT; upload it as CONTRIBUTING.md describes"
      return
    fi
  done
  fail "the video is over $MAX_BYTES bytes at every CRF ($sizes); $OUTPUT is unchanged"
}

case "${1:-}" in
  "") main ;;
  card)
    [[ $# -eq 2 ]] || fail "usage: $0 card <png>"
    command -v magick >/dev/null || fail "magick is missing: brew install imagemagick"
    command -v rsvg-convert >/dev/null || fail "rsvg-convert is missing: brew install librsvg"
    make_card "$2"
    ;;
  *) fail "usage: $0 [card <png>]" ;;
esac
