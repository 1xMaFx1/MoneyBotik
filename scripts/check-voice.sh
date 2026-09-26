#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p .test-build
framework="$PWD/Vendor/build-apple/whisper.xcframework/macos-arm64_x86_64"
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -module-cache-path .test-build/modules -F "$framework" -framework whisper -Xlinker -rpath -Xlinker "$framework" MoneyBotik/ExpenseCore.swift MoneyBotik/LocalTranscriber.swift Tests/VoiceFinanceChecks.swift -o .test-build/VoiceFinanceChecks
say -v Milena -r 145 -o .test-build/finance-voice.aiff 'Зарплата девяносто тысяч рублей. Кофе двести пятьдесят рублей.'
.test-build/VoiceFinanceChecks MoneyBotik/Resources/ggml-base.bin .test-build/finance-voice.aiff
