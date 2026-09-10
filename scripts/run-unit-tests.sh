#!/bin/bash

set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.test-build"
SOURCES=()

for source in \
    "$ROOT/NotchShelf/Core/MenuItemRule.swift" \
    "$ROOT/NotchShelf/Core/MenuItemRuleCodec.swift" \
    "$ROOT/NotchShelf/Core/DisplayConstraint.swift" \
    "$ROOT/NotchShelf/Core/MenuBarGeometry.swift" \
    "$ROOT/NotchShelf/Core/MenuItemSafetyPolicy.swift" \
    "$ROOT/NotchShelf/Core/PreviewSelectionPolicy.swift" \
    "$ROOT/NotchShelf/Core/OverflowPolicy.swift"
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
