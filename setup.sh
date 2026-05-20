#!/bin/bash
set -e

# Claude Ping Setup
# Installs scheduled Claude Code session triggers on macOS

# Always run from the script's own directory so cp commands find the right files
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/claude-ping"
PLIST_DIR="$HOME/Library/LaunchAgents"

mkdir -p "$CONFIG_DIR/logs" "$PLIST_DIR"

# Copy ping.sh and config.yaml (from repo into user config dir)
cp "$SCRIPT_DIR/ping.sh" "$CONFIG_DIR/ping.sh"
chmod +x "$CONFIG_DIR/ping.sh"

[ ! -f "$CONFIG_DIR/config.yaml" ] && cp "$SCRIPT_DIR/config.yaml" "$CONFIG_DIR/config.yaml"

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

echo ""
echo "✓ Claude Ping installed."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "REQUIRED: Schedule Mac wake (run once)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  sudo pmset repeat wake UMTWR ${FIRST_TIME}:00"
echo ""
echo "  This wakes your Mac at your first trigger time (Sun–Thu)."
echo "  Verify: pmset -g sched"
echo "  Remove: sudo pmset repeat cancel"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "USAGE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Test now:  bash ~/.config/claude-ping/ping.sh"
echo "  Logs:      tail -f ~/.config/claude-ping/logs/\$(date +%Y-%m-%d).log"
echo "  Update:    edit ~/.config/claude-ping/config.yaml, then re-run this script"
echo "  Uninstall: for p in ~/Library/LaunchAgents/com.claudeping.*.plist; do launchctl bootout gui/\$(id -u)/\$(basename \$p .plist) && rm \$p; done"
