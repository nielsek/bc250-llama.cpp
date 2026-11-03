#!/bin/sh

# Smoke tests for the llama.cpp build. Prints PASS/FAIL per test, with details
# only on failure. Exits 0 if all tests pass, 1 otherwise.
#
# Speed thresholds can be overridden, e.g. MIN_GEN_TPS=50 ./test.sh

cd "$(dirname "$0")" || exit 1

BIN=llama.cpp/build/bin
MODEL=unsloth/Qwen3.5-9B-GGUF:Q4_K_M
PROMPT="Hello, introduce yourself briefly."
# Reference speeds: prompt ~32.5 t/s (often >100 t/s), generation ~54.1 t/s
MIN_PROMPT_TPS=${MIN_PROMPT_TPS:-30}
MIN_GEN_TPS=${MIN_GEN_TPS:-45}

# Dot as decimal separator in llama.cpp's t/s output, whatever the locale
export LC_NUMERIC=C

TMP=$(mktemp -d) || exit 1
pid=
trap 'rm -rf "$TMP"' EXIT
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null; echo; exit 1' INT TERM

failed=0

# llama-cli catches SIGTERM without exiting, so the model run is wrapped in
# timeout -k, which follows up with SIGKILL when interrupted.

# run NAME OUT ERR CMD...
# Runs CMD with output to OUT/ERR, showing the elapsed time while it runs.
# Returns CMD's exit code.
run() {
  label=$1 out=$2 err=$3
  shift 3
  start=$(date +%s)
  "$@" </dev/null >"$out" 2>"$err" &
  pid=$!
  if [ -t 1 ]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r\033[K....  %s (%ss)' "$label" $(($(date +%s) - start))
      sleep 0.2
    done
    printf '\r\033[K'
  else
    echo "RUN   $label"
  fi
  wait "$pid"
  rc=$?
  pid=
  elapsed=$(($(date +%s) - start))
  return "$rc"
}

pass() {
  echo "PASS  $1 (${elapsed}s)"
}

# fail NAME REASON [OUTPUT_FILE...]
fail() {
  name=$1 reason=$2
  shift 2
  failed=1
  echo "FAIL  $name (${elapsed}s)"
  echo "      $reason"
  for f in "$@"; do
    [ -s "$f" ] || continue
    echo "      --- last 30 lines of $(basename "$f") ---"
    tail -n 30 "$f" | sed 's/^/      /'
  done
  if systemctl is-active --quiet llama-server 2>/dev/null; then
    echo "      note: llama-server is running and may hold GPU memory (./stop.sh)"
  fi
}

# Test 1: the BC-250 is visible as a Vulkan device
name="GPU detection"
run "$name" "$TMP/devices.out" "$TMP/devices.err" "$BIN/llama-cli" --list-devices
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "$name" "llama-cli --list-devices exited with code $rc" \
    "$TMP/devices.out" "$TMP/devices.err"
elif ! grep -Eq 'Vulkan[0-9]+: AMD BC-250 \(RADV' "$TMP/devices.out"; then
  fail "$name" "no 'Vulkan<n>: AMD BC-250 (RADV ...)' device found" \
    "$TMP/devices.out" "$TMP/devices.err"
else
  pass "$name: $(grep -Eo 'Vulkan[0-9]+: AMD BC-250.*' "$TMP/devices.out" | head -n 1)"
fi

# Test 2: download the model, get an answer and check the speed
name="Model introduction"
run "$name" "$TMP/cli.out" "$TMP/cli.err" \
  timeout -k 5 900 "$BIN/llama-cli" -hf "$MODEL" -ngl 99 -st --simple-io \
  --reasoning off -n 256 -p "$PROMPT"
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "$name" "llama-cli exited with code $rc (124 = timed out)" \
    "$TMP/cli.out" "$TMP/cli.err"
else
  # The answer is between the echoed prompt and the "[ Prompt: ... ]" line
  answer=$(awk '/^\[ Prompt:/ { exit } on { print } /^> / { on = 1 }' \
    "$TMP/cli.out" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
  perf=$(grep -E '^\[ Prompt: .* t/s \| Generation: .* t/s \]' "$TMP/cli.out" | tail -n 1)
  prompt_tps=$(echo "$perf" | sed -n 's/.*Prompt: \([0-9.]*\) t\/s.*/\1/p')
  gen_tps=$(echo "$perf" | sed -n 's/.*Generation: \([0-9.]*\) t\/s.*/\1/p')

  if [ -z "$answer" ]; then
    fail "$name" "model gave no answer" "$TMP/cli.out" "$TMP/cli.err"
  elif [ -z "$prompt_tps" ] || [ -z "$gen_tps" ]; then
    fail "$name" "no '[ Prompt: ... | Generation: ... ]' speed line in output" \
      "$TMP/cli.out" "$TMP/cli.err"
  elif awk -v p="$prompt_tps" -v g="$gen_tps" -v mp="$MIN_PROMPT_TPS" -v mg="$MIN_GEN_TPS" \
      'BEGIN { exit !(p < mp || g < mg) }'; then
    fail "$name" "too slow: prompt $prompt_tps t/s (min $MIN_PROMPT_TPS), generation $gen_tps t/s (min $MIN_GEN_TPS)" \
      "$TMP/cli.err"
    echo "      answer: $answer"
  else
    pass "$name: prompt $prompt_tps t/s, generation $gen_tps t/s"
  fi
fi

if [ "$failed" -eq 0 ]; then
  echo "All tests passed"
else
  echo "Some tests failed"
fi
exit "$failed"
