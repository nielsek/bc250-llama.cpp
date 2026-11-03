# bc250-llama.cpp

Scripts to build and run [llama.cpp](https://github.com/ggml-org/llama.cpp)
with Vulkan on an AMD BC-250. The model is served headless by `llama-server`
on port 8000.

## Prerequisites

- [CachyOS](https://cachyos.org/)
- A fully unlocked BC-250, with all CPU cores and GPU CUs enabled
- The GPU governor (`cyan-skillfish-governor-smu`) and the `bc250-cachyos`
  package repository from
  [bc250-toolkit](https://github.com/redbeard1083/bc250-toolkit)

## Usage

- `./build.sh` installs dependencies, then clones and builds llama.cpp
- `./test.sh` checks that the GPU is detected and that a model runs fast enough.
  It prints PASS/FAIL for each test and exits 0 if all pass, 1 otherwise
- `./run.sh` starts `llama-server` in tmux and leaves the desktop to free RAM.
  Attach with `tmux -L llama attach`
- `./stop.sh` stops the server and returns to the desktop
