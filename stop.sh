#!/bin/sh

# Stops the llama-server tmux session started by run.sh and returns to the
# desktop. Stopping the transient unit terminates tmux and llama-server with it.
# The unit is reset if it ended up failed, so run.sh can create it again.

sudo systemctl stop llama-server
sudo systemctl reset-failed llama-server 2>/dev/null

sudo systemctl isolate graphical.target
