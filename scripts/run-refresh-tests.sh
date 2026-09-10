#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/BarTuck-refresh-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
swiftc -parse-as-library \
    "$ROOT"/BarTuck/Core/*.swift "$ROOT"/BarTuck/Models/*.swift \
    "$ROOT"/BarTuck/Services/*.swift "$ROOT/Tests/RefreshIsolationTests.swift" \
    -o "$BUILD_DIR/RefreshIsolationTests"
"$BUILD_DIR/RefreshIsolationTests"
swiftc -parse-as-library "$ROOT/BarTuck/Services/DiagnosticLog.swift" \
    "$ROOT/Tests/DiagnosticLogTests.swift" -o "$BUILD_DIR/DiagnosticLogTests"
"$BUILD_DIR/DiagnosticLogTests"
