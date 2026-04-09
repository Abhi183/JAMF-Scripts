# JAMF Auto-Logout Scripts

Automatically log out inactive macOS lab machines managed by Jamf Pro. Designed for shared computing environments (labs, libraries, kiosks) where idle sessions should be reclaimed.

## Compatibility

| macOS Version | Architecture | Status |
|---|---|---|
| macOS 15 Sequoia | Intel / Apple Silicon | Supported |
| macOS 16–25 | Intel / Apple Silicon | Supported |
| macOS 26 Tahoe | Apple Silicon | Supported |

### What changed for Tahoe

The original scripts relied on APIs deprecated or removed in recent macOS releases:

| Issue | Old Approach | Updated Approach |
|---|---|---|
| Screen lock detection | `ioreg -n IODisplayWrangler` (removed on Apple Silicon) | `CGSessionCopyCurrentDictionary` via python3/objc bridge, with `ScreenSaverEngine` fallback |
| Idle time | `ioreg -c IOHIDSystem` (shallow query) | `ioreg -c IOHIDSystem -d 4` (explicit depth for Apple Silicon reliability) |
| LaunchDaemon loading | `launchctl load` (deprecated since macOS 13) | `launchctl bootstrap system` |
| User logout | `pkill loginwindow` (can crash the system) | AppleScript `«event aevtrlgo»` (graceful logout) |
| App quit loop | `for` loop over `osascript` output (breaks on spaces) | Native AppleScript `repeat` block |
| Log location | `/tmp/` (cleared on reboot) | `/var/log/` (persistent) |
| Console user check | `who` (includes SSH sessions) | `/usr/bin/stat -f%Su /dev/console` (console-only) |

## Scripts

### `auto_logout.sh`

The main script that runs on each trigger:

1. Checks if an interactive user is logged in at the console
2. Reads system idle time via `IOHIDSystem`
3. If idle time exceeds the threshold (default: 15 minutes):
   - **Screen locked**: immediately quits apps and logs out
   - **Screen unlocked**: shows a warning dialog via `jamfHelper` with a countdown; the user can cancel
4. Gracefully quits all foreground applications, then triggers logout via AppleScript

**Configuration** (edit the variables at the top of the script):

| Variable | Default | Description |
|---|---|---|
| `IDLE_THRESHOLD` | `900` | Seconds of inactivity before logout (900 = 15 min) |
| `WARNING_TIMEOUT` | `20` | Seconds the warning dialog stays on screen |
| `JAMF_HELPER` | `/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper` | Path to jamfHelper binary |
| `ICON` | `AlertNoteIcon.icns` | Icon shown in the warning dialog |

### `auto_logout_launchdaemon.sh`

Installs and loads a LaunchDaemon (`com.denison.autologout`) that triggers the Jamf `autologout` policy every 10 minutes. Also disables system sleep so the daemon fires reliably.

## Setup

### Prerequisites

- **Jamf Pro** enrolled machines with the `jamf` binary at `/usr/local/bin/jamf`
- **jamfHelper** installed (ships with the Jamf agent)
- **Root privileges** for daemon installation and logout commands

### 1. Install the LaunchDaemon

Run on each target machine (or deploy via Jamf):

```bash
sudo bash auto_logout_launchdaemon.sh
```

This creates `/Library/LaunchDaemons/com.denison.autologout.plist` and loads it immediately.

### 2. Deploy the logout script via Jamf

1. Upload `auto_logout.sh` to your Jamf Pro console (Settings > Scripts)
2. Create a policy:
   - **Trigger**: Custom event named `autologout`
   - **Execution Frequency**: Ongoing
   - **Script**: `auto_logout.sh`
   - **Scope**: Target lab machines
3. The LaunchDaemon calls `jamf policy -event autologout` every 10 minutes, which runs the script

### 3. Verify

```bash
# Check the daemon is loaded
launchctl print system/com.denison.autologout

# Watch logs
tail -f /var/log/com.denison.autologout.out

# Manually trigger for testing
sudo jamf policy -event autologout
```

## Uninstall

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.denison.autologout.plist
sudo rm /Library/LaunchDaemons/com.denison.autologout.plist
sudo pmset -a sleep 1  # re-enable sleep if desired
```

## Legacy Scripts

The original scripts (`Auto Logout.sh` and `AutoLogout Launch Daemon.sh`) are retained for reference but are not recommended for macOS 13+ or Apple Silicon machines.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Script exits immediately | No console user logged in | Expected behavior — no action needed |
| Warning dialog not shown | `jamfHelper` missing or path changed | Verify path in `JAMF_HELPER` variable |
| Idle time always 0 | `IOHIDSystem` not returning data | Check `ioreg -c IOHIDSystem -d 4 \| grep HIDIdleTime` manually |
| Daemon not firing | `launchctl bootstrap` failed | Check `launchctl print system/com.denison.autologout` for errors |
| Logout not working | TCC or MDM restrictions | Ensure the Jamf agent has Full Disk Access and the script runs as root |
