#!/bin/bash

set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.test-build"
SOURCES=()

for source in \
    "$ROOT/BarTuck/Core/MenuItemRule.swift" \
    "$ROOT/BarTuck/Core/MenuItemRuleCodec.swift" \
    "$ROOT/BarTuck/Core/DisplayConstraint.swift" \
    "$ROOT/BarTuck/Core/MenuBarGeometry.swift" \
    "$ROOT/BarTuck/Core/MenuItemSafetyPolicy.swift" \
    "$ROOT/BarTuck/Core/PreviewSelectionPolicy.swift" \
    "$ROOT/BarTuck/Core/OverflowPolicy.swift"
do
    if [[ -f "$source" ]]; then
        SOURCES+=("$source")
    fi
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

swiftc \
    -parse-as-library \
    "${SOURCES[@]}" \
    "$ROOT/Tests/OverflowPolicyTests.swift" \
    -o "$BUILD_DIR/OverflowPolicyTests"

"$BUILD_DIR/OverflowPolicyTests"

swiftc \
    -parse-as-library \
    "${SOURCES[@]}" \
    "$ROOT/BarTuck/Models/MenuBarItem.swift" \
    "$ROOT/BarTuck/Services/MenuBarWindowServer.swift" \
    "$ROOT/BarTuck/Services/MenuBarScanner.swift" \
    "$ROOT/BarTuck/Core/StatusItemLayoutPolicy.swift" \
    "$ROOT/BarTuck/Services/PermissionManager.swift" \
    "$ROOT/Tests/MenuBarRuntimeTests.swift" \
    -o "$BUILD_DIR/MenuBarRuntimeTests"

"$BUILD_DIR/MenuBarRuntimeTests"
