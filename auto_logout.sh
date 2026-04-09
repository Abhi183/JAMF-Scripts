#!/bin/bash
#
# auto_logout.sh
# Checks user idle time and initiates logout on inactive macOS lab machines.
#
# Compatible with macOS 15 (Sequoia) through macOS 26 (Tahoe),
# including Apple Silicon and Intel.
#
# Deploy via Jamf Pro policy with a recurring trigger (e.g., every 5 minutes).
# Requires root privileges.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
IDLE_THRESHOLD=900          # seconds (15 minutes)
WARNING_TIMEOUT=20          # seconds before auto-logout after warning
JAMF_HELPER="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
ICON="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [auto_logout] $*"; }

# ---------------------------------------------------------------------------
# Pre-flight: exit if no console user is logged in
# ---------------------------------------------------------------------------
console_user=$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || echo "")
if [[ -z "$console_user" || "$console_user" == "root" || "$console_user" == "loginwindow" ]]; then
    log "No interactive console user. Exiting."
    exit 0
fi
log "Console user: $console_user"

# ---------------------------------------------------------------------------
# Get system idle time (seconds)
# Works on both Intel and Apple Silicon across macOS 15–26.
# ---------------------------------------------------------------------------
get_idle_time() {
    local idle_ns
    idle_ns=$(ioreg -c IOHIDSystem -d 4 | awk '/HIDIdleTime/ {print $NF; exit}')
    if [[ -z "$idle_ns" ]]; then
        echo 0
        return
    fi
    echo $(( idle_ns / 1000000000 ))
}

# ---------------------------------------------------------------------------
# Detect whether the screen is locked.
# Uses CGSessionCopyCurrentDictionary via the system python3/objc bridge,
# which works on Apple Silicon and Intel from macOS 12+.
# Falls back to checking for ScreenSaverEngine if python3 is unavailable.
# ---------------------------------------------------------------------------
is_screen_locked() {
    local locked
    locked=$(/usr/bin/python3 -c "
import sys
try:
    import objc
    from Foundation import NSBundle
    CG = NSBundle.bundleWithIdentifier_('com.apple.CoreGraphics')
    functions = [('CGSessionCopyCurrentDictionary', b'@')]
    objc.loadBundleFunctions(CG, globals(), functions)
    d = CGSessionCopyCurrentDictionary()
    if d and d.get('CGSSessionScreenIsLocked', False):
        print('locked')
    else:
        print('unlocked')
except Exception:
    print('unknown')
" 2>/dev/null)

    if [[ "$locked" == "locked" ]]; then
        return 0
    elif [[ "$locked" == "unlocked" ]]; then
        return 1
    fi

    # Fallback: check for ScreenSaverEngine process
    if pgrep -x "ScreenSaverEngine" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Gracefully quit all user applications, then log out.
# ---------------------------------------------------------------------------
force_quit_all_apps_and_logout() {
    log "Force-quitting all user applications..."

    # Quit apps via AppleScript — handles names with spaces correctly
    osascript -e '
        tell application "System Events"
            set appList to name of every application process whose background only is false
            repeat with appName in appList
                try
                    if appName is not "Finder" then
                        tell application appName to quit
                    end if
                end try
            end repeat
        end tell
    ' 2>/dev/null || true

    # Brief pause to let apps close
    sleep 2

    log "Initiating logout..."
    # Graceful logout via AppleScript — works on macOS 15–26 without
    # the risks of killing loginwindow directly.
    osascript -e 'tell application "loginwindow" to «event aevtrlgo»' 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Display a warning dialog via jamfHelper, giving the user a chance to cancel.
# ---------------------------------------------------------------------------
display_logout_warning() {
    if [[ ! -x "$JAMF_HELPER" ]]; then
        log "jamfHelper not found at $JAMF_HELPER — logging out without warning."
        force_quit_all_apps_and_logout
        return
    fi

    local message="You have been idle for a while. This computer will sign you out automatically."
    local button
    button=$("$JAMF_HELPER" \
        -windowType utility \
        -title "Idle Logout Warning" \
        -description "$message" \
        -button1 "Cancel" \
        -button2 "Logout" \
        -timeout "$WARNING_TIMEOUT" \
        -countdown \
        -icon "$ICON" \
        -defaultButton 2 \
        -cancelButton 1 2>/dev/null) || true

    log "jamfHelper returned: $button"

    if [[ "$button" == "0" ]]; then
        log "User cancelled logout."
        exit 0
    fi

    # Button 2 (Logout) or timeout (239) — proceed with logout
    force_quit_all_apps_and_logout
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
idle_time=$(get_idle_time)
log "Idle time: ${idle_time}s (threshold: ${IDLE_THRESHOLD}s)"

if (( idle_time > IDLE_THRESHOLD )); then
    if is_screen_locked; then
        log "Screen is locked — force logout without prompt."
        force_quit_all_apps_and_logout
    else
        log "Screen is unlocked — showing warning dialog."
        display_logout_warning
    fi
else
    log "User is active. No action taken."
fi
