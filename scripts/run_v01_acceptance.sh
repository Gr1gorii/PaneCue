#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${PROJECT_DIR}/build/PaneCue.app"
INFO_PLIST="${APP_DIR}/Contents/Info.plist"
MODEL_FILE="${APP_DIR}/Contents/Resources/Models/panecue-mini-v2.bin"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

fail() {
    echo "acceptance failure: $1" >&2
    exit 1
}

plist_value() {
    "${PLIST_BUDDY}" -c "Print :$1" "${INFO_PLIST}" 2>/dev/null
}

assert_plist_absent() {
    if "${PLIST_BUDDY}" -c "Print :$1" "${INFO_PLIST}" >/dev/null 2>&1; then
        fail "stable bundle unexpectedly contains $1"
    fi
}

echo "[1/5] Running automated acceptance and regression tests"
swift test --package-path "${PROJECT_DIR}"

echo "[2/5] Packaging the stable v0.1 candidate"
"${PROJECT_DIR}/scripts/package_app.sh"

echo "[3/5] Verifying the signed application bundle"
codesign --verify --deep --strict "${APP_DIR}"
[[ -x "${APP_DIR}/Contents/MacOS/PaneCue" ]] \
    || fail "PaneCue executable is missing"

echo "[4/5] Verifying the frozen stable profile"
[[ "$(plist_value CFBundleIdentifier)" == "io.github.gr1gorii.PaneCue" ]] \
    || fail "unexpected stable bundle identifier"
[[ "$(plist_value CFBundleShortVersionString)" == "0.1.0" ]] \
    || fail "unexpected public version"
[[ "$(plist_value PaneCueReleaseProfile)" == "Main" ]] \
    || fail "stable bundle is not using the Main profile"
assert_plist_absent NSScreenCaptureUsageDescription
assert_plist_absent NSAppleEventsUsageDescription
assert_plist_absent NSLocalNetworkUsageDescription

echo "[5/5] Verifying the bundled offline parser"
[[ -s "${MODEL_FILE}" ]] || fail "PaneCue Mini v2 is missing"
MODEL_BYTES="$(stat -f '%z' "${MODEL_FILE}")"
[[ "${MODEL_BYTES}" -le 1048576 ]] \
    || fail "PaneCue Mini v2 exceeds the 1 MiB release budget"

echo "PaneCue v0.1 automated acceptance gate passed"
echo "Manual macOS smoke cases remain in docs/product-freeze/v0.1/v0.1-acceptance.md"
