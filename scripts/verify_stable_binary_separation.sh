#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${1:-${PROJECT_DIR}/build/PaneCue.app}"
INFO_PLIST="${APP_DIR}/Contents/Info.plist"
BINARY="${APP_DIR}/Contents/MacOS/PaneCue"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

fail() {
    echo "binary separation failure: $1" >&2
    exit 1
}

[[ $# -le 1 ]] || fail "usage: verify_stable_binary_separation.sh [PaneCue.app]"
[[ -d "${APP_DIR}" ]] || fail "stable application bundle was not found"
[[ -f "${INFO_PLIST}" ]] || fail "stable Info.plist was not found"
[[ -x "${BINARY}" ]] || fail "stable executable was not found"

codesign --verify --deep --strict "${APP_DIR}" \
    || fail "stable application signature is invalid"

plist_value() {
    "${PLIST_BUDDY}" -c "Print :$1" "${INFO_PLIST}" 2>/dev/null
}

assert_plist_absent() {
    if "${PLIST_BUDDY}" -c "Print :$1" "${INFO_PLIST}" >/dev/null 2>&1; then
        fail "stable Info.plist contains forbidden key $1"
    fi
}

[[ "$(plist_value CFBundleIdentifier)" == "io.github.gr1gorii.PaneCue" ]] \
    || fail "unexpected stable bundle identifier"
[[ "$(plist_value PaneCueReleaseProfile)" == "Main" ]] \
    || fail "bundle is not using the Main release profile"
assert_plist_absent NSScreenCaptureUsageDescription
assert_plist_absent NSAppleEventsUsageDescription
assert_plist_absent NSLocalNetworkUsageDescription

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/panecue-binary-gate.XXXXXX")"
trap 'rm -rf "${TEMP_DIR}"' EXIT
ENTITLEMENTS_PLIST="${TEMP_DIR}/entitlements.plist"
LINKED_FRAMEWORKS="${TEMP_DIR}/linked-frameworks.txt"
BINARY_STRINGS="${TEMP_DIR}/binary-strings.txt"
OBJC_METADATA="${TEMP_DIR}/objc-metadata.txt"

codesign -d --entitlements :- "${APP_DIR}" \
    >"${ENTITLEMENTS_PLIST}" 2>/dev/null \
    || fail "could not read stable entitlements"

ENTITLEMENT_KEYS="$(
    plutil -p "${ENTITLEMENTS_PLIST}" \
        | sed -n 's/^[[:space:]]*"\([^"]*\)".*/\1/p' \
        | LC_ALL=C sort
)"
[[ "${ENTITLEMENT_KEYS}" == "com.apple.security.device.audio-input" ]] \
    || fail "stable entitlements differ from the reviewed allowlist"

otool -L "${BINARY}" >"${LINKED_FRAMEWORKS}"
if grep -Eiq 'ScreenCaptureKit\.framework|Vision\.framework' \
    "${LINKED_FRAMEWORKS}"; then
    fail "stable executable links an experimental capture framework"
fi

strings "${BINARY}" >"${BINARY_STRINGS}"
for marker in \
    "ScreenCaptureKit" \
    "CallVideoPreviewController" \
    "ChromeVideoSessionController" \
    "BrowserVideoRectangleDetector" \
    "RealtimeVoiceCommandController" \
    "OpenAIAPIKeyStore" \
    "OllamaLocalCommandService" \
    "AutoModeController" \
    "AutoModeSuggestionPanelController" \
    "wss://api.openai.com" \
    "https://api.openai.com" \
    "127.0.0.1:11434" \
    "localhost:11434" \
    "execute targetTab javascript" \
    "Allow JavaScript from Apple Events" \
    "__panecuePictureInPictureVideo" \
    "document.pictureInPictureElement" \
    "URLSessionWebSocketTask" \
    "dataTaskWithRequest" \
    "downloadTaskWithRequest" \
    "uploadTaskWithRequest" \
    "NWConnection"
do
    if grep -Fqi -- "${marker}" "${BINARY_STRINGS}"; then
        fail "stable executable contains forbidden marker: ${marker}"
    fi
done

otool -ov "${BINARY}" >"${OBJC_METADATA}"
for selector in \
    configureCloudAccess \
    toggleVoiceCommand \
    toggleAutoMode \
    applyCodeAndCall \
    applyDocumentationAndCode \
    applyNotesAndBrowser \
    showBrowserVideo
do
    if grep -Eq "(^|[[:space:]])${selector}(:|[[:space:]]|$)" \
        "${OBJC_METADATA}"; then
        fail "stable executable contains experimental menu selector: ${selector}"
    fi
done

if find "${APP_DIR}/Contents/Resources" -type f -print \
    | grep -Eiq '/([^/]*(ollama|qwen|functiongemma)[^/]*|[^/]*\.gguf)$'; then
    fail "stable bundle contains an experimental model or runtime resource"
fi

echo "PaneCue stable binary separation gate passed"
