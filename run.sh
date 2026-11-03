#!/bin/sh

tmux new -sllama.cpp -- llama.cpp/build/bin/llama-server \
  -hf unsloth/Qwen3.5-9B-GGUF:Q6_K --no-mmproj \
  -c 131072 --parallel 1 \
  --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 -b 4096 -ub 1024 \
  --reasoning on --reasoning-budget 4096 \
  --reasoning-budget-message "Okay, I have thought about this enough. Time to answer." \
  --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0 --presence-penalty 0 \
  --cache-ram 2048 --host 0.0.0.0 --port 8000
