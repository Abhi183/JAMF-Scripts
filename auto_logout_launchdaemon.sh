#!/bin/bash
#
# auto_logout_launchdaemon.sh
# Installs a LaunchDaemon that triggers the Jamf "autologout" policy
# on a recurring interval.
#
# Compatible with macOS 15 (Sequoia) through macOS 26 (Tahoe).
# Requires root privileges.

set -euo pipefail

PLIST_PATH="/Library/LaunchDaemons/com.denison.autologout.plist"
PLIST_LABEL="com.denison.autologout"

# ---------------------------------------------------------------------------
# Write the LaunchDaemon plist
# ---------------------------------------------------------------------------
cat > "$PLIST_PATH" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.denison.autologout</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/jamf</string>
    <string>policy</string>
    <string>-event</string>
    <string>autologout</string>
  </array>
  <key>StartInterval</key>
  <integer>600</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/com.denison.autologout.out</string>
  <key>StandardErrorPath</key>
  <string>/var/log/com.denison.autologout.err</string>
</dict>
</plist>
PLIST

chmod 644 "$PLIST_PATH"
chown root:wheel "$PLIST_PATH"

# ---------------------------------------------------------------------------
# Load the daemon
# macOS 11+ supports "launchctl bootstrap". The legacy "launchctl load" is
# deprecated as of macOS 13 and may be removed in a future release.
# ---------------------------------------------------------------------------
# Unload first if already loaded (ignore errors on first install)
launchctl bootout system "$PLIST_PATH" 2>/dev/null || true
launchctl bootstrap system "$PLIST_PATH"

echo "LaunchDaemon installed and loaded: $PLIST_LABEL"

# ---------------------------------------------------------------------------
# Disable system sleep so the daemon can fire on schedule
# ---------------------------------------------------------------------------
pmset -a sleep 0
echo "System sleep disabled via pmset."
