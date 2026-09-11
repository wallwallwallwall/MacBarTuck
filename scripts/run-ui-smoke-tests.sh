#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT/.test-build/ui-smoke"
APP="${1:-$ROOT/work/DerivedData-Debug/Build/Products/Debug/MacBarTuck.app}"
EXECUTABLE="$APP/Contents/MacOS/MacBarTuck"
ACTIVE_PID=""
RUN_DIR=""

cleanup() {
    if [[ -n "$ACTIVE_PID" ]] && kill -0 "$ACTIVE_PID" 2>/dev/null; then
        kill "$ACTIVE_PID" 2>/dev/null || true
        wait "$ACTIVE_PID" 2>/dev/null || true
    fi
    if [[ -n "$RUN_DIR" ]]; then
        rm -rf "$RUN_DIR"
    fi
}
trap cleanup EXIT INT TERM

test -x "$EXECUTABLE"
mkdir -p "$BUILD_ROOT"
RUN_DIR="$(mktemp -d "$BUILD_ROOT/run.XXXXXX")"
PROBE="$RUN_DIR/UIPreviewProbe"

swiftc \
    -parse-as-library \
    "$ROOT/Tests/UIPreviewProbe.swift" \
    -o "$PROBE"

run_preview() {
    local name="$1"
    local minimum_width="$2"
    local minimum_height="$3"
    shift 3

    local log="$RUN_DIR/$name.log"
    "$EXECUTABLE" --ui-preview "$@" >"$log" 2>&1 &
    ACTIVE_PID=$!

    if ! "$PROBE" "$ACTIVE_PID" "$minimum_width" "$minimum_height"; then
        cat "$log" >&2
        return 1
    fi

    kill "$ACTIVE_PID" 2>/dev/null || true
    wait "$ACTIVE_PID" 2>/dev/null || true
    ACTIVE_PID=""
    printf '%s: passed\n' "$name"
}

run_language_previews() {
    local language="$1"
    local prefix="$2"

    run_preview "$prefix-status" 700 500 --ui-preview-language="$language" --ui-preview-tab=status
    run_preview "$prefix-items" 700 500 --ui-preview-language="$language" --ui-preview-tab=items
    run_preview "$prefix-preferences" 700 500 --ui-preview-language="$language" --ui-preview-tab=preferences
    run_preview "$prefix-onboarding-welcome" 680 480 --ui-preview-language="$language" --ui-preview-onboarding
    run_preview "$prefix-onboarding-permissions" 680 480 --ui-preview-language="$language" --ui-preview-onboarding --ui-preview-onboarding-step=permissions
    run_preview "$prefix-onboarding-customize" 680 480 --ui-preview-language="$language" --ui-preview-onboarding --ui-preview-onboarding-step=customize
    run_preview "$prefix-onboarding-ready" 680 480 --ui-preview-language="$language" --ui-preview-onboarding --ui-preview-onboarding-step=ready
    run_preview "$prefix-overflow-panel" 600 200 --ui-preview-language="$language" --ui-preview-panel
}

run_language_previews zh-Hans zh
run_language_previews en en

printf 'UIPreviewSmokeTests: 16 passed\n'
