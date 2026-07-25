#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

adapter_path="${1:-training/adapters/qwen3-1.7b-panecue}"
model_tag="${2:-panecue-qwen3:1.0}"
fused_dir="training/fused/qwen3-1.7b-panecue"
ollama_dir="training/ollama/qwen"
llama_cpp_dir="training/tools/llama.cpp"
gguf_venv="training/tools/gguf-venv"

if [[ ! -x .venv-training/bin/mlx_lm.fuse ]]; then
    echo "MLX training environment is missing."
    exit 1
fi

if [[ ! -d "$llama_cpp_dir" ]]; then
    git clone --depth 1 \
        https://github.com/ggml-org/llama.cpp.git \
        "$llama_cpp_dir"
fi

if [[ ! -x "$gguf_venv/bin/python" ]]; then
    uv venv --python 3.12 "$gguf_venv"
    uv pip install \
        --python "$gguf_venv/bin/python" \
        --index-strategy unsafe-best-match \
        -r "$llama_cpp_dir/requirements/requirements-convert_hf_to_gguf.txt"
fi

mkdir -p "$fused_dir" "$ollama_dir"
.venv-training/bin/hf download Qwen/Qwen3-1.7B >/dev/null
.venv-training/bin/mlx_lm.fuse \
    --model Qwen/Qwen3-1.7B \
    --adapter-path "$adapter_path" \
    --save-path "$fused_dir/safetensors"

hf_snapshot_dir="$(find \
    "$HOME/.cache/huggingface/hub/models--Qwen--Qwen3-1.7B/snapshots" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    | head -1)"
for tokenizer_file in \
    tokenizer_config.json \
    tokenizer.json \
    merges.txt \
    vocab.json
do
    cp \
        "$hf_snapshot_dir/$tokenizer_file" \
        "$fused_dir/safetensors/$tokenizer_file"
done

"$gguf_venv/bin/python" \
    "$llama_cpp_dir/convert_hf_to_gguf.py" \
    "$fused_dir/safetensors" \
    --outfile "$fused_dir/panecue-qwen3-1.7b-f16.gguf" \
    --outtype f16

/Applications/Ollama.app/Contents/Resources/llama-quantize \
    "$fused_dir/panecue-qwen3-1.7b-f16.gguf" \
    "$ollama_dir/panecue-qwen3-1.7b-q4_k_m.gguf" \
    Q4_K_M

(
    cd "$ollama_dir"
    /Applications/Ollama.app/Contents/Resources/ollama \
        create \
        "$model_tag" \
        -f Modelfile
)
