#!/bin/bash
set -e

# Stop existing instance if running
echo "Stopping any existing Open Cowork instance..."
pkill -x OpenCowork || true

# Generate project using Tuist (no Xcode auto-open)
echo "Generating Xcode project using Tuist..."
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

# Build using Tuist xcodebuild wrapper with local DerivedData path
echo "Building Open Cowork app..."
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build \
  -scheme OpenCowork \
  -configuration Debug \
  -derivedDataPath .derivedData

# Launch the compiled app
APP_PATH=".derivedData/Build/Products/Debug/OpenCowork.app"
if [ -d "$APP_PATH" ]; then
    echo "Launching Open Cowork from $APP_PATH..."
    nohup "$APP_PATH/Contents/MacOS/OpenCowork" > /dev/null 2>&1 &
    echo "Launched!"
else
    echo "Error: Built app not found at $APP_PATH"
    exit 1
fi
