#!/bin/bash
# AirPlay Receiver: an iPhone, iPad or Mac mirrors its screen (or plays audio) to this computer, like macOS's AirPlay
# Receiver. UxPlay from Fedora; the video is decoded with FFmpeg from RPM Fusion (libavcodec-freeworld), because Fedora's
# own H.264 decoder (OpenH264) corrupts the picture on motion and the corruption stays until the next key frame.
# Runs as nightdrive-airplay.service (bin/airplay-receiver). Run as a regular user; sudo asks for the password.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

"$here/../../setup-rpmfusion.sh" free   # its key checked by fingerprint before its release RPM goes in
sudo dnf install -y uxplay libavcodec-freeworld gstreamer1-plugin-libav
rm -rf "$HOME/.cache/gstreamer-1.0"   # GStreamer's plugin cache: the H.264/HEVC decoders show up at once
"$here/bin/airplay-receiver" enable
echo "AirPlay Receiver on: pick $("$here/bin/airplay-receiver" name) in Screen Mirroring on the iPhone"
