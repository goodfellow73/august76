#!/usr/bin/env bash
set -e

# Check adb is available
if ! command -v adb &>/dev/null; then
  echo "ERROR: 'adb' not found. Install Android Platform Tools first."
  echo "  Mac:   brew install android-platform-tools"
  echo "  Linux: sudo apt install adb"
  echo "  Win:   https://developer.android.com/tools/releases/platform-tools"
  exit 1
fi

# Check a device is connected
DEVICES=$(adb devices | grep -v "List of devices" | grep "device$" | wc -l)
if [ "$DEVICES" -eq 0 ]; then
  echo "ERROR: No Android device found."
  echo "  1. Enable Developer Options on your phone"
  echo "  2. Enable USB Debugging"
  echo "  3. Connect via USB (or run: adb tcpip 5555 && adb connect <phone-ip>:5555)"
  exit 1
fi

echo "Found $DEVICES device(s)."

# Install Python deps
if ! python3 -m pip show fastapi &>/dev/null; then
  python3 -m pip install -r requirements.txt
fi

# Check for ANTHROPIC_API_KEY (optional, needed for AI mode)
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "NOTE: ANTHROPIC_API_KEY not set — AI automation will be disabled."
  echo "  Set it with: export ANTHROPIC_API_KEY=sk-ant-..."
fi

echo ""
echo "Starting Phone Control server..."
echo "Open http://localhost:8765 in your browser"
echo ""

python3 server.py
