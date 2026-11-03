#!/bin/sh

# Starts llama-server in tmux and switches to the non-graphical target, freeing
# the desktop's RAM for the model. tmux runs in a transient system service, so it
# survives the desktop session ending and nothing persists past a reboot.
#
# Attach:  tmux -L llama attach
# Stop:    sudo systemctl stop llama-server
# Desktop: sudo systemctl isolate graphical.target

cd "$(dirname "$0")" || exit 1

sudo systemd-run --unit=llama-server --uid="$(id -u)" --gid="$(id -g)" \
  --working-directory="$PWD" -p Type=forking -p IgnoreOnIsolate=yes \
  tmux -L llama start-server \; set -g remain-on-exit on \; \
  new -d -s llama.cpp -- llama.cpp/build/bin/llama-server \
  -hf unsloth/Qwen3.5-9B-GGUF:Q6_K --no-mmproj \
  -c 131072 --parallel 1 \
  --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 -b 4096 -ub 1024 \
  --spec-default \
  --reasoning on --reasoning-budget 4096 \
  --reasoning-budget-message "Okay, I have thought about this enough. Time to answer." \
  --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0 --presence-penalty 0 \
  --cache-ram 3072 --host 0.0.0.0 --port 8000 || exit 1

# Leave the desktop from a transient service as well, since a terminal running
# this script dies with the desktop. The GPU clock governor is only wanted by
# graphical.target, so start it again or the GPU stays at its idle clock. Then
# switch to the tty1 login prompt instead of the desktop's last frozen frame.
sudo systemd-run --unit=llama-headless --collect -p IgnoreOnIsolate=yes \
  sh -c 'systemctl isolate multi-user.target || exit 1
         systemctl start cyan-skillfish-governor-smu.service
         chvt 1'
