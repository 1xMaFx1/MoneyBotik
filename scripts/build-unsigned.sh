#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodebuild -project MoneyBotik.xcodeproj -scheme MoneyBotik -configuration Release -destination 'generic/platform=iOS' -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build
