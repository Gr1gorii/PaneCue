#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

if [[ ! -x .venv-training/bin/mlx_lm.lora ]]; then
    echo "Training environment is missing. Run:"
    echo "  uv venv --python 3.12 .venv-training"
    echo "  uv pip install --python .venv-training/bin/python 'mlx-lm[train]'"
    exit 1
fi

case "${1:-}" in
    qwen)
        config="training/configs/qwen3-1.7b-lora.yaml"
        ;;
    qwen-hard)
        config="training/configs/qwen3-1.7b-hard-lora.yaml"
        ;;
    functiongemma)
        config="training/configs/functiongemma-270m-lora.yaml"
        ;;
    *)
        echo "Usage: $0 qwen|qwen-hard|functiongemma"
        exit 2
        ;;
esac

.venv-training/bin/mlx_lm.lora --config "$config"
