#!/bin/sh
# Pause / resume the animated wallpaper on one monitor (or all) through mpv's IPC socket.
#   macshell-wallpause.sh <output|all> <pause|resume>
run="${XDG_RUNTIME_DIR:-/tmp}"; v=$([ "$2" = pause ] && echo true || echo false)
msg="{\"command\":[\"set_property\",\"pause\",$v]}"
send_ipc() {
    if command -v socat >/dev/null 2>&1; then
        printf '%s\n' "$msg" | timeout 1 socat -u - "UNIX-CONNECT:$1" >/dev/null 2>&1
    elif command -v nc >/dev/null 2>&1; then
        printf '%s\n' "$msg" | timeout 1 nc -U -N "$1" >/dev/null 2>&1
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(1); s.connect(sys.argv[1]); s.sendall((sys.argv[2]+"\n").encode()); s.close()' "$1" "$msg" >/dev/null 2>&1
    fi
}
for s in "$run"/macshell-mpv-*.sock; do
    [ -S "$s" ] || continue
    case "$1" in all) ;; *) [ "$s" = "$run/macshell-mpv-$1.sock" ] || continue ;; esac
    send_ipc "$s"
done
