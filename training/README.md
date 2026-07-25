# PaneCue local-model training

PaneCue fine-tunes small local models only for safe voice-command routing.
The dataset contains Russian and English commands, custom scenarios,
negations, unrelated requests, and ambiguous phrases.

## PaneCue Mini (default)

PaneCue Mini is the production offline command model. It combines a
quantized, hashed language classifier with 499,975 learned parameters and
deterministic extraction of
application names, window sizes, positions, custom scenario names, and
explicit negations. The current v2 binary is about 500 KB and does not require
Ollama.

```sh
.venv-training/bin/python scripts/train_panecue_mini.py
swift test --filter paneCueMiniStaysTinyAndRoutesHeldOutCommands
```

The end-to-end hybrid path must route at least 98% of the held-out dataset.
Dynamic commands such as “open VS Code and make Notes a little smaller” are
covered separately by parser tests.

## Optional transformer experiments

Qwen and FunctionGemma are retained only as opt-in experiments. They are not
bundled with PaneCue and are never loaded by the default local mode.

## Generate the deterministic dataset

```sh
.venv-training/bin/python scripts/generate_training_data.py
```

## Baseline evaluation

```sh
.venv-training/bin/python scripts/evaluate_local_model.py qwen3:1.7b
.venv-training/bin/python scripts/evaluate_local_model.py functiongemma:270m
```

The selected PaneCue Qwen checkpoint improved held-out action accuracy from
27.1% to 82.9%. Iteration 50 was selected by early stopping. A later
contrastive adapter was rejected because its overall accuracy fell to 74.3%.

## Train on Apple Silicon

```sh
scripts/train_local_model.sh qwen
scripts/train_local_model.sh qwen-hard
scripts/train_local_model.sh functiongemma
```

## Export the selected Qwen adapter

```sh
scripts/export_qwen_to_ollama.sh
```

FunctionGemma requires accepting Google's model license on Hugging Face and
authenticating with a Hugging Face access token. Training data and adapters
remain on this Mac.

The held-out test split must improve before an adapter is exported into
PaneCue. A lower validation loss alone is not sufficient.
