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

echo "[1/7] Running automated acceptance and regression tests"
swift test --package-path "${PROJECT_DIR}"
swift build --package-path "${PROJECT_DIR}" --product PaneCue
swift build --package-path "${PROJECT_DIR}" --product PaneCueExperimental

echo "[2/7] Packaging the stable v0.2 development candidate"
"${PROJECT_DIR}/scripts/package_app.sh"

echo "[3/7] Verifying the signed application bundle"
codesign --verify --deep --strict "${APP_DIR}"
[[ -x "${APP_DIR}/Contents/MacOS/PaneCue" ]] \
    || fail "PaneCue executable is missing"

echo "[4/7] Verifying the frozen stable profile"
[[ "$(plist_value CFBundleIdentifier)" == "io.github.gr1gorii.PaneCue" ]] \
    || fail "unexpected stable bundle identifier"
[[ "$(plist_value CFBundleShortVersionString)" == "0.2.0" ]] \
    || fail "unexpected public version"
[[ "$(plist_value CFBundleVersion)" == "14" ]] \
    || fail "unexpected build number"
[[ "$(plist_value LSMinimumSystemVersion)" == "26.0" ]] \
    || fail "unexpected minimum system version"
[[ "$(plist_value PaneCueReleaseProfile)" == "Main" ]] \
    || fail "stable bundle is not using the Main profile"
[[ "$(lipo -archs "${APP_DIR}/Contents/MacOS/PaneCue")" == "arm64" ]] \
    || fail "stable executable is not arm64-only"
assert_plist_absent NSScreenCaptureUsageDescription
assert_plist_absent NSAppleEventsUsageDescription
assert_plist_absent NSLocalNetworkUsageDescription

echo "[5/7] Verifying physical Stable/Experimental separation"
"${PROJECT_DIR}/scripts/verify_stable_binary_separation.sh" "${APP_DIR}"

echo "[6/7] Verifying the bundled offline parser"
[[ -s "${MODEL_FILE}" ]] || fail "PaneCue Mini v2 is missing"
MODEL_BYTES="$(stat -f '%z' "${MODEL_FILE}")"
[[ "${MODEL_BYTES}" -le 1048576 ]] \
    || fail "PaneCue Mini v2 exceeds the 1 MiB release budget"

echo "[7/7] Verifying release tooling"
bash -n \
    "${PROJECT_DIR}/scripts/package_app.sh" \
    "${PROJECT_DIR}/scripts/verify_stable_binary_separation.sh" \
    "${PROJECT_DIR}/scripts/build_release_dmg.sh"
plutil -lint \
    "${PROJECT_DIR}/Resources/Info.plist" \
    "${PROJECT_DIR}/Resources/Info-Experimental.plist" \
    "${PROJECT_DIR}/Resources/PaneCue.entitlements" \
    "${PROJECT_DIR}/Resources/PaneCue-Experimental.entitlements" >/dev/null
grep -q '^Mozilla Public License Version 2.0$' \
    "${PROJECT_DIR}/LICENSE" \
    || fail "MPL-2.0 license identity changed"
"${PROJECT_DIR}/scripts/build_release_dmg.sh" --help >/dev/null

echo "PaneCue v0.2 development identity gate passed"
echo "Manual v0.2 smoke cases remain frozen in docs/product-freeze/v0.2/v0.2-acceptance.md"
