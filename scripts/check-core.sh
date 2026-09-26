#!/bin/zsh
set -eu
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "${0:A:h}/.."
mkdir -p .test-build
SWIFTC=$(xcrun --find swiftc)
SDK=$(xcrun --sdk macosx --show-sdk-path)
for suite in CoreChecks StoreChecks FinanceChecks; do
  sources=(MoneyBotik/ExpenseCore.swift)
  if [[ "$suite" != CoreChecks ]]; then sources+=(MoneyBotik/ExpenseStore.swift); fi
  "$SWIFTC" -sdk "$SDK" -module-cache-path .test-build/modules "${sources[@]}" "Tests/$suite.swift" -o ".test-build/$suite"
  ".test-build/$suite"
done
