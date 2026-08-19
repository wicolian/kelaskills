#!/usr/bin/env bash
# install-launchd.sh - tier 5 on macOS: a watchdog that survives a reboot.
#
# WRITES a LaunchAgent plist and tells you the command to load it.
# It does NOT load it for you - starting a background daemon on someone's
# machine is their call, not a script's.
#
#   WD_ROOT=/path/to/programme WD_START='...' ./install-launchd.sh
#
# Remove it later with:
#   launchctl bootout gui/$(id -u)/<label>
#   (then delete the plist yourself if you want it gone)
set -euo pipefail
ROOT="${WD_ROOT:?set WD_ROOT to the programme root}"
START="${WD_START:?set WD_START to the command that starts one orchestrator}"
LABEL="${LAUNCHD_LABEL:-dev.blackoutproof.watchdog}"
WATCHDOG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/watchdog.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents" "$ROOT/artifacts"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$WATCHDOG</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>WD_ROOT</key><string>$ROOT</string>
    <key>WD_START</key><string>$START</string>
    <key>WD_INTERVAL</key><string>${WD_INTERVAL:-600}</string>
    <key>WD_MAX_RESTARTS</key><string>${WD_MAX_RESTARTS:-12}</string>
    <key>PATH</key><string>$PATH</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key>
  <dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$ROOT/artifacts/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$ROOT/artifacts/launchd.err.log</string>
</dict>
</plist>
PLISTEOF

echo "wrote $PLIST"
echo
echo "Load it (this is the step that makes it reboot-proof):"
echo "  launchctl bootstrap gui/\$(id -u) \"$PLIST\""
echo
echo "Check it:   launchctl print gui/\$(id -u)/$LABEL | head -20"
echo "Stop it:    launchctl bootout  gui/\$(id -u)/$LABEL"
echo
echo "KeepAlive.SuccessfulExit=false means: restart it if it crashes, but let it"
echo "stay stopped when it exits 0 (all work complete) or exits 1 (crash-loop"
echo "guard tripped). That is deliberate - both are decisions, not failures."
