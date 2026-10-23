#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/promo
swiftc -O -module-cache-path build/promo/ModuleCache media/promo/render.swift -o build/promo/render
python3 media/promo/sound.py build/promo/score.wav
build/promo/render --icons | ffmpeg -hide_banner -y -f rawvideo -pixel_format bgra -video_size 1920x1080 -framerate 60 -i pipe:0 -i build/promo/score.wav -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -af volume=12dB -c:a aac -b:a 192k -t 30 -movflags +faststart -map_metadata -1 -metadata title="Styleus — Your Pencil. Your Mac." -metadata artist="Styleus contributors" -metadata comment="Original illustrated interaction demo" media/promo/styleus-promo.mp4
build/promo/render --still 17.3 media/promo/styleus-promo-poster.png
ffprobe -v error -show_entries format=duration:stream=codec_name,width,height,r_frame_rate -of json media/promo/styleus-promo.mp4
