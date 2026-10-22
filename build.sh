#!/bin/zsh
# Builds Dictate.app, installs it to /Applications and restarts the LaunchAgent.
set -euo pipefail
cd "${0:A:h}"

swift build -c release
APP=build/Dictate.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Dictate" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/Dictate.icns "$APP/Contents/Resources/"
# Same certificate every build, so Accessibility and Microphone permissions survive.
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"')
codesign --force --sign "$IDENTITY" "$APP"

rm -rf /Applications/Dictate.app
ditto "$APP" /Applications/Dictate.app
launchctl kickstart -k "gui/$(id -u)/com.ravibandaru.dictate"
echo "Installed and restarted Dictate"
