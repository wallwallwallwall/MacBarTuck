#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MacBarTuck-panel-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
ditto "$ROOT/MacBarTuck/Resources/zh-Hans.lproj" "$BUILD_DIR/zh-Hans.lproj"
ditto "$ROOT/MacBarTuck/Resources/en.lproj" "$BUILD_DIR/en.lproj"
swiftc -parse-as-library \
    "$ROOT"/MacBarTuck/Core/*.swift "$ROOT"/MacBarTuck/Models/*.swift \
    "$ROOT"/MacBarTuck/Services/*.swift "$ROOT"/MacBarTuck/Panel/*.swift \
    "$ROOT"/MacBarTuck/UI/*.swift "$ROOT/Tests/OverflowPanelInteractionTests.swift" \
    "$ROOT/MacBarTuck/App/StatusBarController.swift" \
    -o "$BUILD_DIR/OverflowPanelInteractionTests"
"$BUILD_DIR/OverflowPanelInteractionTests"
