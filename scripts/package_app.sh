#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${PROJECT_DIR}/build/PaneCue.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
RUNTIME_DIR="${RESOURCES_DIR}/Runtime"
MODELS_DIR="${RESOURCES_DIR}/Models"

swift build --package-path "${PROJECT_DIR}" -c release

mkdir -p "${MACOS_DIR}" "${RUNTIME_DIR}" "${MODELS_DIR}"
cp -f "${PROJECT_DIR}/.build/release/PaneCue" "${MACOS_DIR}/PaneCue"
cp -f "${PROJECT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
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

codesign \
    --force \
    --deep \
    --sign - \
    --requirements '=designated => identifier "io.github.gr1gorii.PaneCue"' \
    "${APP_DIR}" >/dev/null

echo "${APP_DIR}"
