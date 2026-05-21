#!/bin/bash
set -e

# Claude Ping Setup
# Installs scheduled Claude Code session triggers on macOS

# Always run from the script's own directory so cp commands find the right files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/claude-ping"
PLIST_DIR="$HOME/Library/LaunchAgents"

mkdir -p "$CONFIG_DIR/logs" "$PLIST_DIR"

# Copy ping.sh and config.yaml from repo, always overwriting installed copies
cp "$SCRIPT_DIR/ping.sh" "$CONFIG_DIR/ping.sh"
chmod +x "$CONFIG_DIR/ping.sh"
cp "$SCRIPT_DIR/config.yaml" "$CONFIG_DIR/config.yaml"

# Read schedule times from config.yaml (no pyyaml dependency — grep-based, BSD sed safe)
# Strip comments before extracting times to avoid matching times mentioned in comment text
TIMES=$(grep -E '^\s*-\s+"?[0-9]{2}:[0-9]{2}"?' "$CONFIG_DIR/config.yaml" | sed 's/#.*//' | grep -oE '[0-9]{2}:[0-9]{2}')
FIRST_TIME=$(echo "$TIMES" | head -1)

if [ -z "$TIMES" ]; then
  echo "ERROR: No schedule times found in config.yaml. Add entries under 'schedule:'." >&2
  exit 1
fi

# Unload and remove existing claude-ping plists (using modern launchctl API)
for EXISTING in "$PLIST_DIR"/com.claudeping.*.plist; do
  [ -f "$EXISTING" ] || continue
  LABEL=$(basename "$EXISTING" .plist)
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$EXISTING"
done

# Generate and load a plist for each scheduled time
for TIME in $TIMES; do
  HOUR=$(echo "$TIME" | cut -d: -f1 | sed 's/^0*//' | tr -d '[:space:]')
  MIN=$(echo "$TIME"  | cut -d: -f2 | sed 's/^0*//' | tr -d '[:space:]')
  # Default to 0 if stripping leading zeros leaves empty string (e.g. "00")
  HOUR=${HOUR:-0}
  MIN=${MIN:-0}
  LABEL="com.claudeping.$(printf '%02d%02d' "$HOUR" "$MIN")"
  PLIST="$PLIST_DIR/$LABEL.plist"

  cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$CONFIG_DIR/ping.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$HOUR</integer>
        <key>Minute</key>
        <integer>$MIN</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$CONFIG_DIR/logs/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>$CONFIG_DIR/logs/launchd-error.log</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || true
  echo "Loaded: $LABEL (fires at $(printf '%02d:%02d' "$HOUR" "$MIN") local time)"
done

# Schedule Mac wake via pmset (requires sudo)
echo ""
#echo "Scheduling Mac wake at ${FIRST_TIME} every working day (Sun–Thu)..."
#if sudo pmset repeat wake UMTWR "${FIRST_TIME}:00"; then
#  echo "✓ Mac wake scheduled at ${FIRST_TIME} (Sun–Thu)"
echo "Scheduling Mac wake at ${FIRST_TIME} every weekday..."
if sudo pmset repeat wake UMTWRFS "${FIRST_TIME}:00"; then
  echo "✓ Mac wake scheduled at ${FIRST_TIME}"
else
  echo "⚠ pmset failed — you may need to run manually:"
  echo "  sudo pmset repeat wake UMTWR ${FIRST_TIME}:00"
fi

echo ""
echo "✓ Claude Ping installed."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "USAGE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Test now:  bash ~/.config/claude-ping/ping.sh"
echo "  Logs:      tail -f ~/.config/claude-ping/logs/\$(date +%Y-%m-%d).log"
echo "  Update:    edit config.yaml in the repo, then re-run this script"
echo "  Wake sched: pmset -g sched"
echo "  Uninstall: for p in ~/Library/LaunchAgents/com.claudeping.*.plist; do launchctl bootout gui/\$(id -u)/\$(basename \$p .plist) && rm \$p; done"
