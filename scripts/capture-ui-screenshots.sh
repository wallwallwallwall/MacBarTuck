#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/work/DerivedData-Debug/Build/Products/Debug/MacBarTuck.app}"
EXECUTABLE="$APP/Contents/MacOS/MacBarTuck"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MacBarTuck-screenshots.XXXXXX")"
PROBE="$RUN_DIR/UIPreviewProbe"
ACTIVE_PID=""

cleanup() {
    if [[ -n "$ACTIVE_PID" ]] && kill -0 "$ACTIVE_PID" 2>/dev/null; then
        kill "$ACTIVE_PID" 2>/dev/null || true
        wait "$ACTIVE_PID" 2>/dev/null || true
    fi
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT INT TERM

test -x "$EXECUTABLE"
swiftc -parse-as-library "$ROOT/Tests/UIPreviewProbe.swift" -o "$PROBE"

capture_preview() {
    local output="$1"
    local minimum_width="$2"
    local minimum_height="$3"
    shift 3

    "$EXECUTABLE" --ui-preview "$@" >"$RUN_DIR/preview.log" 2>&1 &
    ACTIVE_PID=$!
    local window_id
    window_id="$($PROBE "$ACTIVE_PID" "$minimum_width" "$minimum_height" --window-id)"
    screencapture -x -o -l "$window_id" "$ROOT/docs/screenshots/$output"
    kill "$ACTIVE_PID" 2>/dev/null || true
    wait "$ACTIVE_PID" 2>/dev/null || true
    ACTIVE_PID=""
    printf '%s: captured\n' "$output"
}

capture_language_previews() {
    local language="$1"
    local suffix="$2"

    capture_preview "settings$suffix.png" 700 500 --ui-preview-language="$language" --ui-preview-tab=status
    capture_preview "items$suffix.png" 700 500 --ui-preview-language="$language" --ui-preview-tab=items
    capture_preview "preferences$suffix.png" 700 500 --ui-preview-language="$language" --ui-preview-tab=preferences
    capture_preview "onboarding$suffix.png" 680 480 --ui-preview-language="$language" --ui-preview-onboarding
    capture_preview "onboarding-permissions$suffix.png" 680 480 --ui-preview-language="$language" --ui-preview-onboarding --ui-preview-onboarding-step=permissions
    capture_preview "onboarding-customize$suffix.png" 680 480 --ui-preview-language="$language" --ui-preview-onboarding --ui-preview-onboarding-step=customize
    capture_preview "onboarding-ready$suffix.png" 680 480 --ui-preview-language="$language" --ui-preview-onboarding --ui-preview-onboarding-step=ready
    capture_preview "overflow-panel$suffix.png" 600 200 --ui-preview-language="$language" --ui-preview-panel
}

capture_language_previews zh-Hans ""
capture_language_previews en "-en"

printf 'UI screenshots: 16 captured\n'
