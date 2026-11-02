#!/bin/sh

echo "###"
echo "Test 1: GPU detection"

echo "# Expected output:"
echo "Available devices:
  Vulkan0: AMD BC-250 (RADV GFX1013) (12800 MiB, 12273 MiB free)"

echo "# Actual output:"
./llama.cpp/build/bin/llama-cli --list-devices

echo
echo "###"
echo "Test 2: Download model and make it introduce itself"

echo "# Expected tokens/sec:"
echo "[ Prompt: 32.5 t/s | Generation: 54.1 t/s ]"

echo "# Actual prompt / tokens/sec"

./llama.cpp/build/bin/llama-cli -hf unsloth/Qwen3.5-9B-GGUF:Q4_K_M -ngl 99 -p "Hello, introduce yourself briefly."
