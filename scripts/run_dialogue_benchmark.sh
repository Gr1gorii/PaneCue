#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_FILE="${PROJECT_DIR}/training/panecue-mini/panecue-mini-v2.bin"

if [[ "$#" -ne 1 || "$1" != /* ]]; then
    echo "usage: $0 /absolute/external/corpus-directory" >&2
    exit 2
fi

swift run \
    --package-path "${PROJECT_DIR}" \
    PaneCueDialogueBenchmark \
    --corpus "$1" \
    --repository "${PROJECT_DIR}" \
    --model "${MODEL_FILE}"
