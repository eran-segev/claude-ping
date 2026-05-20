#!/bin/bash
# Claude Ping — start the Claude Code Pro 5-hour session window
# Reads config and calls claude CLI in print mode (non-interactive, exits after response)

# launchd runs with a minimal PATH — extend it so `claude` is found
export PATH="/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

CONFIG="$HOME/.config/claude-ping/config.yaml"
LOG_DIR="$HOME/.config/claude-ping/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"

if [ ! -f "$CONFIG" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') — ERROR: config not found at $CONFIG. Run setup.sh." >> "$LOG_FILE"
  exit 1
fi

# Parse config (grep-based, no pyyaml dependency, BSD sed safe)
GREETING=$(grep -E '^greeting:' "$CONFIG" 2>/dev/null | sed 's/^greeting:[[:space:]]*//' | tr -d '"' || echo "Starting new work session.")
SLEEP_AFTER=$(grep -E '^sleep_after_trigger:' "$CONFIG" 2>/dev/null | sed 's/^sleep_after_trigger:[[:space:]]*//' | tr -d ' ' || echo "false")

echo "$(date '+%Y-%m-%d %H:%M:%S') — Starting Claude session (sleep_after=$SLEEP_AFTER)" >> "$LOG_FILE"

# Network check with retries:
#   - Mac may take 10-15s to reconnect after waking from sleep
#   - Intermittent reception may need a longer wait
# Retry schedule: immediate (15s timeout) → +10s → +5min → give up
network_ok() {
  ping -c 1 -t 15 api.anthropic.com >/dev/null 2>&1
}

if ! network_ok; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') — Network not ready, retrying in 10s..." >> "$LOG_FILE"
  sleep 10
  if ! network_ok; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') — Still no network, retrying in 5min (intermittent connection)..." >> "$LOG_FILE"
    sleep 300
    if ! network_ok; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') — SKIP: no network after retries" >> "$LOG_FILE"
      exit 0
    fi
  fi
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') — Network OK, calling claude" >> "$LOG_FILE"

# timeout 30: prevents hanging if OAuth needs interactive re-auth
# -p = print mode: sends prompt, prints response, exits immediately (no persistent session)
timeout 30 claude -p "$GREETING" >> "$LOG_FILE" 2>&1
EXIT_CODE=$?

echo "$(date '+%Y-%m-%d %H:%M:%S') — Done (exit: $EXIT_CODE)" >> "$LOG_FILE"

# Put Mac back to sleep ONLY if user has been idle for 5+ minutes
# (idle = Mac was woken for this job, not interrupted mid-work)
if [ "$SLEEP_AFTER" = "true" ]; then
  IDLE_NS=$(ioreg -c IOHIDSystem -d 3 -n IOHIDSystem 2>/dev/null | grep HIDIdleTime | awk -F= '{print $2}' | tr -d ' ')
  IDLE_SECS=$(( ${IDLE_NS:-0} / 1000000000 ))
  if [ "$IDLE_SECS" -gt 300 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') — Idle ${IDLE_SECS}s, sleeping Mac" >> "$LOG_FILE"
    sleep 2  # let log flush before sleep
    pmset sleepnow
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') — User active (idle ${IDLE_SECS}s), skipping sleep" >> "$LOG_FILE"
  fi
fi
