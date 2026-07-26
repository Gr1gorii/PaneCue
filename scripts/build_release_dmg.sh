#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
INFO_PLIST="${PROJECT_DIR}/Resources/Info.plist"
APP_DIR="${PROJECT_DIR}/build/PaneCue.app"
OUTPUT_DIR="${PROJECT_DIR}/build/release"
SIGN_IDENTITY="${PANECUE_CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${PANECUE_NOTARY_PROFILE:-}"
SKIP_NOTARIZATION=false

usage() {
    cat <<'EOF'
usage: build_release_dmg.sh [options]

Options:
  --identity IDENTITY       Developer ID Application certificate name
  --notary-profile PROFILE  notarytool Keychain profile
  --output-dir DIRECTORY    artifact destination (default: build/release)
  --skip-notarization       create a signed candidate without submitting it
  --adhoc                   create a local-only ad-hoc DMG for smoke testing
  --help                    show this help

The identity and notary profile can also be supplied through
PANECUE_CODESIGN_IDENTITY and PANECUE_NOTARY_PROFILE.
EOF
}

fail() {
    echo "release failure: $1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity)
            [[ $# -ge 2 ]] || { usage >&2; exit 64; }
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --notary-profile)
            [[ $# -ge 2 ]] || { usage >&2; exit 64; }
            NOTARY_PROFILE="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || { usage >&2; exit 64; }
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --skip-notarization)
            SKIP_NOTARIZATION=true
            shift
            ;;
        --adhoc)
            SIGN_IDENTITY="-"
            SKIP_NOTARIZATION=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done

[[ -n "${SIGN_IDENTITY}" ]] \
    || fail "pass --identity or set PANECUE_CODESIGN_IDENTITY"

if [[ "${SKIP_NOTARIZATION}" == false ]]; then
    [[ "${SIGN_IDENTITY}" != "-" ]] \
        || fail "an ad-hoc build cannot be notarized"
    [[ -n "${NOTARY_PROFILE}" ]] \
        || fail "pass --notary-profile or set PANECUE_NOTARY_PROFILE"
fi

if [[ "${SIGN_IDENTITY}" != "-" ]]; then
    security find-identity -v -p codesigning \
        | grep -F "\"${SIGN_IDENTITY}\"" >/dev/null \
        || fail "codesigning identity was not found in the Keychain"
fi

VERSION="$("${PLIST_BUDDY}" -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD_NUMBER="$("${PLIST_BUDDY}" -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
ARCHITECTURE="$(uname -m)"
DMG_NAME="PaneCue-${VERSION}-build${BUILD_NUMBER}-${ARCHITECTURE}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/panecue-release.XXXXXX")"

cleanup() {
    rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

mkdir -p "${OUTPUT_DIR}"
rm -f "${DMG_PATH}"

"${PROJECT_DIR}/scripts/package_app.sh" --sign-identity "${SIGN_IDENTITY}"
codesign --verify --deep --strict "${APP_DIR}"

cp -R "${APP_DIR}" "${STAGING_DIR}/PaneCue.app"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
    -volname "PaneCue ${VERSION}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null

hdiutil verify "${DMG_PATH}" >/dev/null

if [[ "${SIGN_IDENTITY}" != "-" ]]; then
    codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${DMG_PATH}"
    codesign --verify --strict "${DMG_PATH}"
fi

if [[ "${SKIP_NOTARIZATION}" == false ]]; then
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait
    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"
else
    echo "Notarization skipped; this artifact is for local qualification only."
fi

echo "Artifact: ${DMG_PATH}"
shasum -a 256 "${DMG_PATH}"
