#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MacBarTuck-refresh-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
swiftc -parse-as-library \
    "$ROOT"/MacBarTuck/Core/*.swift "$ROOT"/MacBarTuck/Models/*.swift \
    "$ROOT"/MacBarTuck/Services/*.swift "$ROOT/Tests/RefreshIsolationTests.swift" \
    -o "$BUILD_DIR/RefreshIsolationTests"
"$BUILD_DIR/RefreshIsolationTests"
swiftc -parse-as-library "$ROOT/MacBarTuck/Services/DiagnosticLog.swift" \
    "$ROOT/Tests/DiagnosticLogTests.swift" -o "$BUILD_DIR/DiagnosticLogTests"
"$BUILD_DIR/DiagnosticLogTests"
