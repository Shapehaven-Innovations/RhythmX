#!/bin/bash
# Prints the UDID of the "RhythmX Test iPhone" simulator, creating it if needed.
NAME="RhythmX Test iPhone"
id=$(xcrun simctl list devices available | grep "$NAME" | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}')
if [ -z "$id" ]; then
  runtime=$(xcrun simctl list runtimes available | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-26-[0-9]+' | tail -1)
  [ -z "$runtime" ] && runtime=$(xcrun simctl list runtimes available | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-18-[0-9]+' | tail -1)
  id=$(xcrun simctl create "$NAME" "iPhone 16 Pro" "$runtime")
fi
echo "$id"
