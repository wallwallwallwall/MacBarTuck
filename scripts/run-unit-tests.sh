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

swiftc -parse-as-library "${SOURCES[@]}" \
    "$ROOT/BarTuck/Models/MenuBarItem.swift" \
    "$ROOT/BarTuck/Services/MenuBarWindowServer.swift" \
    "$ROOT/BarTuck/Services/MenuBarScanner.swift" \
    "$ROOT/Tests/MenuBarIdentityTests.swift" \
    "$ROOT/BarTuck/Services/MenuBarItemActivator.swift" \
    "$ROOT/BarTuck/Services/MenuBarEventRelay.swift" \
    "$ROOT/BarTuck/Services/PreferencesStore.swift" \
    "$ROOT/BarTuck/Services/MenuBarCaptureService.swift" \
    -o "$BUILD_DIR/MenuBarIdentityTests"
"$BUILD_DIR/MenuBarIdentityTests"

swiftc -parse-as-library "${SOURCES[@]}" \
    "$ROOT/BarTuck/Models/MenuBarItem.swift" \
    "$ROOT/BarTuck/Services/PreferencesStore.swift" \
    "$ROOT/BarTuck/App/DockVisibilityController.swift" \
    "$ROOT/BarTuck/App/AppMenuController.swift" \
    "$ROOT/Tests/AppAccessTests.swift" \
    -o "$BUILD_DIR/AppAccessTests"
"$BUILD_DIR/AppAccessTests"

swiftc -parse-as-library \
    "$ROOT/BarTuck/Services/PermissionManager.swift" \
    "$ROOT/Tests/PermissionStateTests.swift" \
    -o "$BUILD_DIR/PermissionStateTests"
"$BUILD_DIR/PermissionStateTests"
