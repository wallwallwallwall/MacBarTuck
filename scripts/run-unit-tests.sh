#!/bin/bash

set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.test-build"
SOURCES=()

for source in \
    "$ROOT/MacBarTuck/UI/AppLocalization.swift" \
    "$ROOT/MacBarTuck/Core/MenuItemRule.swift" \
    "$ROOT/MacBarTuck/Core/MenuItemRuleCodec.swift" \
    "$ROOT/MacBarTuck/Core/DisplayConstraint.swift" \
    "$ROOT/MacBarTuck/Core/MenuBarGeometry.swift" \
    "$ROOT/MacBarTuck/Core/MenuItemSafetyPolicy.swift" \
    "$ROOT/MacBarTuck/Core/MenuItemVisibility.swift" \
    "$ROOT/MacBarTuck/Core/MenuBarInteractionPolicy.swift" \
    "$ROOT/MacBarTuck/Core/PreviewSelectionPolicy.swift" \
    "$ROOT/MacBarTuck/Core/OverflowPolicy.swift"
do
    if [[ -f "$source" ]]; then
        SOURCES+=("$source")
    fi
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
ditto "$ROOT/MacBarTuck/Resources/zh-Hans.lproj" "$BUILD_DIR/zh-Hans.lproj"
ditto "$ROOT/MacBarTuck/Resources/en.lproj" "$BUILD_DIR/en.lproj"

swiftc \
    -parse-as-library \
    "${SOURCES[@]}" \
    "$ROOT/Tests/OverflowPolicyTests.swift" \
    -o "$BUILD_DIR/OverflowPolicyTests"

"$BUILD_DIR/OverflowPolicyTests"

swiftc \
    -parse-as-library \
    "${SOURCES[@]}" \
    "$ROOT/MacBarTuck/Models/MenuBarItem.swift" \
    "$ROOT/MacBarTuck/Services/MenuBarWindowServer.swift" \
    "$ROOT/MacBarTuck/Services/MenuBarScanner.swift" \
    "$ROOT/MacBarTuck/Core/StatusItemLayoutPolicy.swift" \
    "$ROOT/MacBarTuck/Services/PermissionManager.swift" \
    "$ROOT/Tests/MenuBarRuntimeTests.swift" \
    -o "$BUILD_DIR/MenuBarRuntimeTests"

"$BUILD_DIR/MenuBarRuntimeTests"

swiftc -parse-as-library "${SOURCES[@]}" \
    "$ROOT/MacBarTuck/Models/MenuBarItem.swift" \
    "$ROOT/MacBarTuck/Services/MenuBarWindowServer.swift" \
    "$ROOT/MacBarTuck/Services/MenuBarScanner.swift" \
    "$ROOT/Tests/MenuBarIdentityTests.swift" \
    "$ROOT/MacBarTuck/Services/MenuBarItemActivator.swift" \
    "$ROOT/MacBarTuck/Services/MenuBarEventRelay.swift" \
    "$ROOT/MacBarTuck/Services/PreferencesStore.swift" \
    "$ROOT/MacBarTuck/Services/MenuBarCaptureService.swift" \
    "$ROOT/MacBarTuck/Services/DiagnosticLog.swift" \
    -o "$BUILD_DIR/MenuBarIdentityTests"
"$BUILD_DIR/MenuBarIdentityTests"

swiftc -parse-as-library "${SOURCES[@]}" \
    "$ROOT/MacBarTuck/Models/MenuBarItem.swift" \
    "$ROOT/MacBarTuck/Services/PreferencesStore.swift" \
    "$ROOT/MacBarTuck/App/DockVisibilityController.swift" \
    "$ROOT/MacBarTuck/App/AppMenuController.swift" \
    "$ROOT/Tests/AppAccessTests.swift" \
    -o "$BUILD_DIR/AppAccessTests"
"$BUILD_DIR/AppAccessTests"

swiftc -parse-as-library \
    "$ROOT/MacBarTuck/UI/AppLocalization.swift" \
    "$ROOT/MacBarTuck/Services/PermissionManager.swift" \
    "$ROOT/Tests/PermissionStateTests.swift" \
    -o "$BUILD_DIR/PermissionStateTests"
"$BUILD_DIR/PermissionStateTests"

swiftc \
    -parse-as-library \
    "$ROOT/MacBarTuck/UI/AppLocalization.swift" \
    "$ROOT/MacBarTuck/Core/DisplayConstraint.swift" \
    "$ROOT/MacBarTuck/Models/DisplaySnapshot.swift" \
    "$ROOT/Tests/LocalizationTests.swift" \
    -o "$BUILD_DIR/LocalizationTests"
"$BUILD_DIR/LocalizationTests"
