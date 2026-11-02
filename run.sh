#!/bin/sh

tmux new -sllama.cpp -- llama.cpp/build/bin/llama-server -hf unsloth/Qwen3.5-9B-GGUF:Q4_K_M --jinja -c 393216 --parallel 3 --flash-attn on --cache-type-k q4_0 --cache-type-v q4_0 --reasoning off --host 0.0.0.0 --port 8080 -b 8192 -ub 1024 --cache-ram 2048
