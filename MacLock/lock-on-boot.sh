#!/bin/sh
# Lock the session immediately on Hyprland startup when boot-locking is enabled.
# Triggered by ~/.config/hypr/macshell.lua on hyprland.start.
set -u

[ -n "${WAYLAND_DISPLAY:-}" ] || exit 0
command -v qs >/dev/null 2>&1 || exit 0

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
[ -f "$CONF/macshell/env" ] && . "$CONF/macshell/env"

FLAG_FILE="$CONF/maclock/lock-on-boot"
enabled=0
case "${MACLOCK_ON_BOOT:-}" in
    1|true|yes|on) enabled=1 ;;
    0|false|no|off) enabled=0 ;;
    *)
        if [ -f "$FLAG_FILE" ]; then
            val=$(tr -d '[:space:]' < "$FLAG_FILE" 2>/dev/null || true)
            case "$val" in
                1|true|yes|on) enabled=1 ;;
            esac
        fi
        ;;
esac

[ "$enabled" = 1 ] || exit 0

# Safety: never lock the user out if MacLock or PAM (/etc/pam.d/hyprlock) is missing.
[ -f "$CONF/quickshell/MacLock/shell.qml" ] || exit 0
[ -e /etc/pam.d/hyprlock ] || exit 0

# Avoid spawning duplicate MacLock instances.
if pgrep -u "$(id -u)" -f '(^|/)(qs|quickshell)( .*)? (-c|--config) MacLock( |$)' >/dev/null 2>&1; then
    exit 0
fi

# Wait briefly for the Wayland socket to be ready (up to 5 s).
rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
i=0
while [ "$i" -lt 50 ]; do
    [ -S "$rt/$WAYLAND_DISPLAY" ] && break
    i=$((i + 1))
    sleep 0.1
done

qs -c MacLock >/dev/null 2>&1 &
