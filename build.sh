#!/bin/sh

sudo pacman -S tmux base-devel cmake vulkan-headers vulkan-icd-loader vulkan-tools vulkan-radeon spirv-headers

git clone https://github.com/ggerganov/llama.cpp

cd llama.cpp

cmake -B build -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc)
