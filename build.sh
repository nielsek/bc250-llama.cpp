#!/bin/sh

# FIXME - note repo for vulkan-radeon:
# bc250-cachyos/vulkan-radeon         3:26.2.5-1.346  3:26.2.5-1.346    0.00 MiB

sudo pacman -S tmux base-devel cmake vulkan-headers vulkan-icd-loader vulkan-tools vulkan-radeon spirv-headers

git clone https://github.com/ggerganov/llama.cpp

cd llama.cpp

cmake -B build -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc)
