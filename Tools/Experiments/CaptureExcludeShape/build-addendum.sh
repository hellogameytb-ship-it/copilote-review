#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
mkdir -p build/retours-17
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun clang++ -std=c++17 -fobjc-arc -O1 -Wall -Wextra \
  -mmacosx-version-min=14.0 -framework AppKit -framework CoreGraphics -framework ScreenCaptureKit -framework CoreMedia -framework CoreVideo -framework QuartzCore \
  Tools/Experiments/CaptureExcludeShape/addendum.mm -o build/retours-17/capture-shape-addendum
