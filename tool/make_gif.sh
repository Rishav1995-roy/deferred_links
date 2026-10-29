#!/bin/bash
# Assembles build/demo_frames/*.png into doc/demo.gif (needs ffmpeg).
set -e
cd "$(dirname "$0")/.."
ffmpeg -y -loglevel error -framerate 10 -i build/demo_frames/f%03d.png \
  -vf "scale=340:-1:flags=lanczos,palettegen=max_colors=96:stats_mode=diff" build/palette.png
ffmpeg -y -loglevel error -framerate 10 -i build/demo_frames/f%03d.png -i build/palette.png \
  -lavfi "scale=340:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5" -loop 0 doc/demo.gif
ls -l doc/demo.gif
