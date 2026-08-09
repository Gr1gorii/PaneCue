#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="main"
APP_NAME="PaneCue"
PRODUCT_NAME="PaneCue"
EXECUTABLE_NAME="PaneCue"
INFO_PLIST="${PROJECT_DIR}/Resources/Info.plist"
BUNDLE_ID="io.github.gr1gorii.PaneCue"
ENTITLEMENTS="${PROJECT_DIR}/Resources/PaneCue.entitlements"
SIGN_IDENTITY="${PANECUE_CODESIGN_IDENTITY:--}"

usage() {
    cat <<'EOF'
usage: package_app.sh [--experimental] [--sign-identity IDENTITY]

Without --sign-identity, the app receives an ad-hoc signature for local use.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --experimental)
            PROFILE="experimental"
            APP_NAME="PaneCue Experimental"
            PRODUCT_NAME="PaneCueExperimental"
            EXECUTABLE_NAME="PaneCueExperimental"
            INFO_PLIST="${PROJECT_DIR}/Resources/Info-Experimental.plist"
            BUNDLE_ID="io.github.gr1gorii.PaneCue.experimental"
            ENTITLEMENTS="${PROJECT_DIR}/Resources/PaneCue-Experimental.entitlements"
            shift
            ;;
        --sign-identity)
            [[ $# -ge 2 ]] || { usage >&2; exit 64; }
            SIGN_IDENTITY="$2"
            shift 2
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

APP_DIR="${PROJECT_DIR}/build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
RUNTIME_DIR="${RESOURCES_DIR}/Runtime"
MODELS_DIR="${RESOURCES_DIR}/Models"

swift build \
    --package-path "${PROJECT_DIR}" \
    -c release \
    --product "${PRODUCT_NAME}"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RUNTIME_DIR}" "${MODELS_DIR}"
cp -f \
    "${PROJECT_DIR}/.build/release/${EXECUTABLE_NAME}" \
    "${MACOS_DIR}/PaneCue"
cp -f "${INFO_PLIST}" "${CONTENTS_DIR}/Info.plist"
cp -f "${PROJECT_DIR}/Resources/PaneCue.icns" \
    "${RESOURCES_DIR}/PaneCue.icns"
cp -f "${PROJECT_DIR}/Resources/AppIcon.png" \
    "${RESOURCES_DIR}/AppIcon.png"
cp -f "${PROJECT_DIR}"/Resources/AppIcon-{Default,Dark,Clear-Light,Clear-Dark}.png \
    "${RESOURCES_DIR}/"
cp -f "${PROJECT_DIR}"/Resources/AppIcon-Tinted-*.png \
    "${RESOURCES_DIR}/"
cp -f "${PROJECT_DIR}/Resources/PaneCue-Mark-Transparent.png" \
    "${RESOURCES_DIR}/PaneCue-Mark-Transparent.png"
cp -f "${PROJECT_DIR}/Resources/PaneCueStatusTemplate.png" \
    "${RESOURCES_DIR}/PaneCueStatusTemplate.png"
chmod +x "${MACOS_DIR}/PaneCue"

rm -f \
    "${RUNTIME_DIR}/ollama" \
    "${MODELS_DIR}/panecue-qwen3-1.7b-q4_k_m.gguf" \
    "${MODELS_DIR}/panecue-mini-v1.bin"

PANECUE_MINI_SOURCE="${PROJECT_DIR}/training/panecue-mini/panecue-mini-v2.bin"
if [[ -f "${PANECUE_MINI_SOURCE}" ]]; then
    cp -f \
        "${PANECUE_MINI_SOURCE}" \
        "${MODELS_DIR}/panecue-mini-v2.bin"
else
    echo "error: trained PaneCue Mini model was not found" >&2
    exit 1
fi

SIGN_ARGUMENTS=(
    --force
    --deep
    --sign "${SIGN_IDENTITY}"
    --entitlements "${ENTITLEMENTS}"
)

if [[ "${SIGN_IDENTITY}" != "-" ]]; then
    SIGN_ARGUMENTS+=(--options runtime --timestamp)
else
    SIGN_ARGUMENTS+=(
        --requirements "=designated => identifier \"${BUNDLE_ID}\""
    )
fi

codesign "${SIGN_ARGUMENTS[@]}" "${APP_DIR}" >/dev/null
codesign --verify --deep --strict "${APP_DIR}"

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    echo "${APP_DIR} (${PROFILE}, ad-hoc signed)"
else
    echo "${APP_DIR} (${PROFILE}, signed by ${SIGN_IDENTITY})"
fi
