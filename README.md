# Claude Ping

Automatically starts your Claude Code Pro session at scheduled times each day — even when your Mac is sleeping.

## The problem it solves

Claude Code Pro usage resets on a 5-hour rolling window. If you start at 9 AM you hit the limit around noon. If it starts at 7 AM it resets at noon instead. The problem is remembering (or being awake) to trigger it. Claude Ping does it for you.

## Requirements

- macOS (Apple Silicon or Intel)
- [Claude Code CLI](https://claude.ai/code) installed and authenticated (run `claude` once to log in)

## Install

```bash
git clone <this-repo>
cd claude-ping
bash setup.sh
```

setup.sh configures launchd and schedules the Mac wake automatically (requires `sudo` for the `pmset` step).

## Configure

Edit `config.yaml` in the repo:

```yaml
schedule:
  - "06:00"   # First trigger — also used as your Mac wake time
  - "11:02"   # Second trigger (Mac is awake by now, no wake needed)

greeting: "Starting a new work session."

sleep_after_trigger: true
# true  = put Mac back to sleep after trigger if idle 5+ min
# false = leave Mac awake
```

After editing, re-run `bash setup.sh` to apply. setup.sh always copies this file into place and updates both launchd and the Mac wake schedule.

## Schedule Mac wake

setup.sh handles this automatically — it runs `sudo pmset repeat wake UMTWRFS <first-trigger-time>` at the end of installation. You'll be prompted for your password once.

To verify or change the wake schedule manually:

```bash
# Check current schedule
pmset -g sched

# Change wake time (adjust days/time as needed)
# Days: M=Mon T=Tue W=Wed R=Thu F=Fri S=Sat U=Sun
sudo pmset repeat wake UMTWRFS 06:00:00

# Remove
sudo pmset repeat cancel
```

For midday and afternoon triggers the Mac is already on — no wake needed.

## How it works

1. Mac wakes at scheduled time (via `pmset`)
2. launchd fires `ping.sh`
3. `ping.sh` checks for network (retries up to 5 min for slow connections)
4. Runs `claude -p "<greeting>"` — this starts your Claude Code Pro 5-hour window
5. If Mac was idle (you weren't using it), puts it back to sleep

If the Mac was sleeping and couldn't wake (battery, no charger), launchd fires the missed job the moment you open the lid.

## Logs

```bash
# Live log for today
tail -f ~/.config/claude-ping/logs/$(date +%Y-%m-%d).log

# launchd errors (check here if triggers aren't firing)
cat ~/.config/claude-ping/logs/launchd-error.log
```

## Test

```bash
bash ~/.config/claude-ping/ping.sh
```

Output prints directly to the terminal and to the log file.

## Update schedule

Edit `config.yaml` in the repo, then re-run:

```bash
bash setup.sh
```

## Uninstall

```bash
for p in ~/Library/LaunchAgents/com.claudeping.*.plist; do
  launchctl bootout gui/$(id -u)/$(basename $p .plist) && rm $p
done
sudo pmset repeat cancel
rm -rf ~/.config/claude-ping
```
