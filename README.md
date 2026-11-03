# bc250-llama.cpp

Scripts to build and run [llama.cpp](https://github.com/ggml-org/llama.cpp)
with Vulkan on an AMD BC-250. The model is served headless by `llama-server`
on port 8000, for use as a coding model from [opencode](https://opencode.ai).

## Prerequisites

- [CachyOS](https://cachyos.org/)
- A fully unlocked BC-250, with all CPU cores and GPU CUs enabled
- The GPU governor (`cyan-skillfish-governor-smu`), the `bc250-cachyos`
  package repository and the `ttm.pages_limit=3145728` kernel parameter (which
  lets the GPU use up to 12 GiB of system memory) from
  [bc250-toolkit](https://github.com/redbeard1083/bc250-toolkit)

## Usage

- `./build.sh` installs dependencies, then clones and builds llama.cpp
- `./test.sh` checks that the GPU is detected and that a model runs fast enough.
  It prints PASS/FAIL for each test and exits 0 if all pass, 1 otherwise
- `./run.sh` starts `llama-server` in tmux and leaves the desktop to free RAM.
  Attach with `tmux -L llama attach`
- `./stop.sh` stops the server and returns to the desktop

In opencode, point a model entry at `http://<host>:8000/v1` and declare the
context size the server actually has, or opencode will send more than fits:
`"limit": { "context": 131072, "output": 32768 }`.

## Memory budget

The BC-250 has 16 GB of GDDR6 shared by the CPU and GPU. 512 MiB is carved out
for the GPU in the BIOS, the firmware takes ~0.6 GiB, and Linux sees the
remaining 14.8 GiB. The GPU may use up to 12 GiB of that, set by the
`ttm.pages_limit` kernel parameter that bc250-toolkit installs (without it the
kernel's default allows only half of RAM); the Vulkan driver reports the GPU as
integrated, so
llama.cpp places everything in this shared memory. Since it is all the same
memory, a bigger BIOS carve-out would not make anything faster.

With the settings below the server takes about 9.4 GiB of the 12 GiB GPU
allowance (7.5 GiB weights, 2.1 GiB KV cache, working buffers) plus up to
3 GiB of RAM for the prompt cache. That is why `run.sh` leaves the desktop:
Plasma and its apps take ~3 GiB, which headless operation gives back.

## Why Qwen3.5-9B, Q6_K

`unsloth/Qwen3.5-9B-GGUF:Q6_K`, which `llama-server` downloads into
`~/.cache/huggingface/` on first start.

- **9B** is the largest Qwen3.5 that fits the 12 GiB GPU allowance with a
  128K context at a good quantization. The 27B and 35B-A3B models only fit at
  2–3 bits, which leaves little room for context and degrades quality, and the
  27B would process prompts roughly 3× slower. Measured on this machine, the
  9B reads prompts at ~400 t/s and generates at ~40 t/s.
- **Qwen3.5** is a hybrid model: only every 4th layer is full attention, the
  rest use a recurrent state. Its KV cache is therefore small (2.1 GiB for
  128K tokens at q8_0), which is what makes a 128K context affordable on
  12 GiB. It also thinks before answering, which a model this small needs for
  coding and tool use, and has a native 262K context.
- **Q6_K** is close to the unquantized model in quality. Compared to Q4_K_M it
  costs 1.7 GiB more and drops generation from ~57 to ~40 t/s, which still
  fits comfortably. Q8_0 would cost another ~2 GiB and ~15% speed for a
  barely measurable gain.
- **unsloth's** GGUFs are quantized with an importance matrix, which helps at
  the same bit width.

## llama-server flags

Every flag in `run.sh`, and why. Speeds were measured on this BC-250.

| Flag | Reason |
|---|---|
| `-hf unsloth/Qwen3.5-9B-GGUF:Q6_K` | Fetch (once) and load the model from Hugging Face. See above. |
| `--no-mmproj` | The repo ships a 0.9 GB vision projector that `-hf` would also load. opencode is text only, so skip it. |
| `-c 131072` | 128K context. Qwen recommends at least 128K for thinking tasks, and agentic sessions with tool output get long. Costs 2.1 GiB at q8_0. |
| `--parallel 1` | One server slot. opencode holds one conversation at a time, and the context is divided between slots, so more slots means less context each. |
| `--flash-attn on` | Faster attention on long contexts and required for a quantized KV cache. |
| `--cache-type-k q8_0 --cache-type-v q8_0` | 8-bit KV cache. The original guide used q4_0, which hurts quality on long contexts and was also slower: at a 16K-token depth, q4_0 ran 329 t/s prompt / 45 t/s generation, q8_0 394 / 48, f16 394 / 50. q8_0 is near lossless at half the size of f16. |
| `-b 4096 -ub 1024` | Logical and physical batch size for prompt processing. `-ub 1024` was the fastest measured (256: 446 t/s, 512: 452, 1024: 465, 2048: 438). `-b 4096` lets long prompts be submitted in larger chunks. |
| `--spec-default` | N-gram speculative decoding: the server guesses upcoming tokens from text already in the context and the model verifies them in one pass. Output is identical and no draft model is needed. On a code-editing request generation went from 43 to ~82 t/s with 84% of guesses accepted; plain chat stayed at 40 t/s. |
| `--reasoning on` | Let the model think before answering, as it is trained to. Noticeably better coding and tool-use answers from a 9B model. |
| `--reasoning-budget 4096` | Cap the thinking. The model overthinks: it took 1,400–2,400 tokens to settle on `s[::-1]` for a one-liner and once ran 8,000 tokens without answering, which in opencode looks like a hang. 4096 tokens is ~100 s at 40 t/s. Raise it if answers feel rushed, lower it if waits are too long. |
| `--reasoning-budget-message "..."` | Text injected into the thinking when the budget runs out, so the model closes its thinking cleanly and answers instead of being cut off mid-thought. Verified to still give correct answers at a 1024 budget. |
| `--temp 0.6 --top-p 0.95 --top-k 20 --min-p 0 --presence-penalty 0` | Qwen's recommended sampling for "thinking mode, precise coding tasks" (from the model card). llama.cpp's defaults are `temp 0.8 top-k 40 min-p 0.05`. Qwen's general-chat preset uses `presence-penalty 1.5`, but the coding preset uses 0, and that is what matters for opencode. |
| `--cache-ram 3072` | Keep up to 3 GiB of processed prompts in RAM, so switching between opencode chats or sub-agents does not reprocess a long prompt (~30 s for 12K tokens). Roughly 60K tokens per GiB. 3 GiB is affordable because the desktop is not running. |
| `--host 0.0.0.0 --port 8000` | Listen on all interfaces so opencode on another machine can reach the server. |

Not used, and why:

- `--cache-reuse`: lets the server shift cached chunks when the start of a
  prompt changes. Qwen3.5's recurrent layers cannot be shifted; the server
  already keeps context checkpoints (32 per slot by default) to recover when
  opencode rewrites earlier parts of a prompt.
- `-ngl`: all layers go to the GPU by default in `llama-server`.

## Headless operation

`run.sh` starts tmux inside a transient systemd service (`llama-server`) so
it survives the desktop session ending, then switches to `multi-user.target`
from a second transient service, because the terminal running the script dies
with the desktop. Leaving `graphical.target` also stops the GPU governor,
which leaves the GPU at its 500 MHz idle clock (about 4× slower), so the
governor is started again, and `chvt 1` switches to the tty1 login prompt
instead of the desktop's last frozen frame. Transient services vanish on
reboot and the default target stays graphical, so nothing persists.
