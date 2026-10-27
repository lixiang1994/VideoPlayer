#!/bin/sh
# 无版权动态测试图与正弦波；试听素材编码前峰值约 -12 dBFS，长时自动化素材保留低振幅。
# ffmpeg sine 自带约 1/8 的幅度；试听素材使用 volume=2，而非再次衰减到几乎无声。
set -eu
fixture_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/Fixtures"
mkdir -p "$fixture_dir"
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=320x180:rate=15:duration=24' -f lavfi -i 'sine=frequency=440:duration=24' -af volume=2 -c:v libx264 -preset fast -pix_fmt yuv420p -g 15 -b:v 120k -c:a aac -b:a 32k -movflags +faststart -y "$fixture_dir/sample.mp4"
ffmpeg -nostdin -hide_banner -loglevel error -i "$fixture_dir/sample.mp4" -c copy -y "$fixture_dir/second.mp4"
ffmpeg -nostdin -hide_banner -loglevel error -i "$fixture_dir/sample.mp4" -t 0.6 -c copy -y "$fixture_dir/short.mp4"
ffmpeg -nostdin -hide_banner -loglevel error -i "$fixture_dir/sample.mp4" -c copy -y "$fixture_dir/sample.mov"
ffmpeg -nostdin -hide_banner -loglevel error -display_rotation:v:0 90 -i "$fixture_dir/sample.mp4" -c copy -y "$fixture_dir/rotated.mp4"
ffmpeg -nostdin -hide_banner -loglevel error -i "$fixture_dir/sample.mp4" -t 5 -an -c:v copy -y "$fixture_dir/silent.mp4"
ffmpeg -nostdin -hide_banner -loglevel error -i "$fixture_dir/sample.mp4" -t 5 -c:v libx265 -preset fast -x265-params log-level=error -tag:v hvc1 -c:a copy -movflags +faststart -y "$fixture_dir/hevc.mp4"
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=160x90:rate=10:duration=180' -f lavfi -i 'sine=frequency=440:duration=180' -af volume=0.02 -c:v libx264 -preset fast -pix_fmt yuv420p -g 10 -b:v 48k -c:a aac -b:a 16k -movflags +faststart -y "$fixture_dir/long.mp4"
ffmpeg -nostdin -hide_banner -loglevel error -i "$fixture_dir/sample.mp4" -c copy -f hls -hls_time 4 -hls_playlist_type vod -hls_segment_filename "$fixture_dir/video%02d.ts" -y "$fixture_dir/video.m3u8"
