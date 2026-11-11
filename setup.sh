#!/usr/bin/env bash
# ==============================================================================
# MacShell & MacLock (Tahoe / Liquid Glass Edition) - Arch Linux One-Liner Setup
# Fork: https://github.com/hrithikramprasath/MacShell
# ==============================================================================
set -euo pipefail

# If piped via `curl ... | bash`, re-attach stdin to the active terminal
if [ ! -t 0 ] && [ -e /dev/tty ]; then
    exec < /dev/tty
fi

# Visual styling
if [ -t 1 ]; then
    BOLD=$'\033[1m'; GREEN=$'\033[32m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'
    YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
    BOLD=""; GREEN=""; BLUE=""; CYAN=""; YELLOW=""; RED=""; RESET=""
fi

log_step()  { printf '%s==>%s %s%s%s\n' "$CYAN" "$RESET" "$BOLD" "$*" "$RESET"; }
log_ok()    { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
log_info()  { printf '  %sℹ%s %s\n' "$BLUE" "$RESET" "$*"; }
log_warn()  { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
log_error() { printf '%serror:%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

echo "${BOLD}${CYAN}"
cat << 'EOF'
 __  __            ____  _          _ _ 
|  \/  | __ _  ___/ ___|| |__   ___| | |
| |\/| |/ _` |/ __\___ \| '_ \ / _ \ | |
| |  | | (_| | (__ ___) | | | |  __/ | |
|_|  |_|\__,_|\___|____/|_| |_|\___|_|_|
   Liquid Glass + Audio Hub + MacLock (Arch Linux)
EOF
echo "${RESET}"

# 1. Distro Verification
log_step "Checking operating system..."
if [ ! -f /etc/arch-release ] && ! have pacman; then
    log_warn "This automated one-liner is specialized for Arch Linux."
    printf "Continue anyway? [y/N] "
    read -r ans
    case "$ans" in [Yy]*) ;; *) log_error "Aborted by user.";; esac
else
    log_ok "Arch Linux detected"
fi

# Ensure sudo credentials upfront
log_step "Requesting sudo privileges for package management..."
if [ "$(id -u)" -ne 0 ]; then
    if ! sudo -v; then
        log_error "sudo is required to install dependencies."
    fi
    # Keep sudo alive during installation
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# 2. Arch Linux Native Dependencies
log_step "Installing Arch Linux official dependencies (pacman)..."
ARCH_PKGS=(
    git base-devel hyprland hypridle
    pipewire wireplumber pipewire-pulse pipewire-alsa libmysofa
    bluez bluez-utils usb_modeswitch networkmanager wireless-regdb iw
    python python-pip playerctl brightnessctl ddcutil libnotify
    grim slurp wf-recorder wl-clipboard
    socat jq inotify-tools imagemagick
    nautilus kitty papirus-icon-theme
    qt6-base qt6-declarative qt6-multimedia qt6-shadertools qt6-wayland qt6-svg
)
sudo pacman -S --needed --noconfirm "${ARCH_PKGS[@]}"
log_ok "Official repository packages installed"

# Ensure Bluetooth daemon is enabled and running
if have systemctl; then
    sudo systemctl enable --now bluetooth.service 2>/dev/null || true
    log_ok "Bluetooth service enabled"
fi

# Apply wireless regulatory domain from system locale if unconfigured
if have iw; then
    current_reg=$(iw reg get 2>/dev/null | awk '/country/ {print $2}' | tr -d ':' | head -n1 || true)
    if [ -z "$current_reg" ] || [ "$current_reg" = "00" ]; then
        loc_country=$(locale 2>/dev/null | awk -F= '/LC_TIME|LANG/ {print $2}' | grep -o '[A-Z]\{2\}' | head -n1 || true)
        if [ -n "$loc_country" ]; then
            sudo iw reg set "$loc_country" 2>/dev/null || true
            log_ok "Wireless regulatory domain set to $loc_country"
        fi
    fi
fi

# 3. AUR Helper & Quickshell Setup
log_step "Checking AUR helper and Quickshell..."
AUR_HELPER=""
if have yay; then
    AUR_HELPER="yay"
elif have paru; then
    AUR_HELPER="paru"
else
    log_info "No AUR helper found. Bootstrapping yay-bin..."
    TMP_YAY=$(mktemp -d)
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$TMP_YAY"
    (cd "$TMP_YAY" && makepkg -si --noconfirm)
    rm -rf "$TMP_YAY"
    AUR_HELPER="yay"
    log_ok "yay-bin installed successfully"
fi

if ! have qs && ! have quickshell; then
    log_info "Installing quickshell from AUR ($AUR_HELPER)..."
    "$AUR_HELPER" -S --needed --noconfirm quickshell-git || "$AUR_HELPER" -S --needed --noconfirm quickshell
    log_ok "quickshell installed"
else
    log_ok "quickshell is already installed"
fi

# Optional wallpaper daemon from AUR if neither swww nor awww is found
if ! have awww && ! have swww && ! have mpvpaper; then
    log_info "Installing awww wallpaper daemon from AUR..."
    "$AUR_HELPER" -S --needed --noconfirm awww-git || "$AUR_HELPER" -S --needed --noconfirm swww || true
fi

# 4. Clone or Update Fork Repository (~/MacShell)
REPO_DIR="${HOME}/MacShell"
log_step "Setting up MacShell repository in $REPO_DIR..."
if [ -d "$REPO_DIR/.git" ]; then
    log_info "Existing repository detected. Updating to latest main..."
    cd "$REPO_DIR"
    git remote set-url origin https://github.com/hrithikramprasath/MacShell.git 2>/dev/null || true
    git fetch origin main
    git checkout main
    git pull --ff-only origin main || true
else
    log_info "Cloning hrithikramprasath/MacShell..."
    git clone -b main https://github.com/hrithikramprasath/MacShell.git "$REPO_DIR"
    cd "$REPO_DIR"
fi

# Configure upstream remote for seamless future 3-way merges
if ! git remote get-url upstream >/dev/null 2>&1; then
    git remote add upstream https://github.com/0-ss/MacShell.git
    log_ok "Configured upstream remote -> https://github.com/0-ss/MacShell.git"
fi

# 5. Deploy Components via install.sh
log_step "Deploying MacShell, MacLock, and components..."
export MACSHELL_REPO="hrithikramprasath/MacShell"
export MACSHELL_BRANCH="main"
export MACSHELL_CHANNEL="main"

bash "$REPO_DIR/install.sh" --yes --local --channel main --no-deps

# 6. Configure Environment & Lock Screen Settings
log_step "Configuring styles, icons, and lockscreen presets..."
mkdir -p "${HOME}/.config/macshell"
cat > "${HOME}/.config/macshell/env" << 'EOF'
# MacShell Environment Configuration
export MACSHELL_REPO=hrithikramprasath/MacShell
export MACSHELL_BRANCH=main
export MACSHELL_CHANNEL=main
export QS_ICON_THEME=Papirus-Dark
EOF

# Lockscreen settings: mediaSlot bottom (under password/avatar)
mkdir -p "${HOME}/.config/maclock"
cat > "${HOME}/.config/maclock/settings.json" << 'EOF'
{
  "mediaSlot": "bottom"
}
EOF
log_ok "Configured MacLock settings (mediaSlot: bottom)"

# Configure Hypridle with MacLock IPC
mkdir -p "${HOME}/.config/hypr"
if [ ! -f "${HOME}/.config/hypr/hypridle.conf" ] || ! grep -q "lock-via-ipc.sh" "${HOME}/.config/hypr/hypridle.conf"; then
    cat > "${HOME}/.config/hypr/hypridle.conf" << 'EOF'
general {
    lock_cmd = sh ~/.config/quickshell/MacLock/lock-via-ipc.sh
    before_sleep_cmd = sh ~/.config/quickshell/MacLock/lock-via-ipc.sh
}

# Auto-lock after 5 minutes of inactivity (300 seconds)
listener {
    timeout = 300
    on-timeout = sh ~/.config/quickshell/MacLock/lock-via-ipc.sh
}

# Turn off displays after 10 minutes of inactivity (600 seconds)
listener {
    timeout = 600
    on-timeout = hyprctl dispatch dpms off
    on-resume = hyprctl dispatch dpms on
}
EOF
    log_ok "Configured ~/.config/hypr/hypridle.conf"
fi

# Ensure Hyprland Lua configuration has proper reload guard
LUA_CONF="${HOME}/.config/hypr/hyprland.lua"
if [ ! -f "$LUA_CONF" ] && [ -f "$REPO_DIR/config/hypr/hyprland.lua" ]; then
    log_info "Deploying starter MacShell Hyprland Lua configuration..."
    install -m 644 "$REPO_DIR/config/hypr/hyprland.lua" "$LUA_CONF"
    log_ok "Installed ~/.config/hypr/hyprland.lua"
elif [ -f "$LUA_CONF" ]; then
    if grep -qF 'require("macshell")' "$LUA_CONF" && ! grep -qF 'package.loaded["macshell"] = nil' "$LUA_CONF"; then
        sed -i 's/require("macshell")/package.loaded["macshell"] = nil\nrequire("macshell")/' "$LUA_CONF"
        log_ok "Added config reload keybind fix to hyprland.lua"
    fi
fi

# 7. Install Helper Tools & Upstream Sync Utility
log_step "Installing helper tools into ~/.local/bin..."
mkdir -p "${HOME}/.local/bin" "${HOME}/.config/macshell" "${HOME}/.config/systemd/user"
for tool in mac-discord-ctl mac-earbuds-ctl mac-media-ctl mac-shot-full mac-shot-region mac-record-toggle; do
    [ -f "$REPO_DIR/MacShell/assets/$tool" ] && install -m 755 "$REPO_DIR/MacShell/assets/$tool" "${HOME}/.local/bin/$tool"
done
[ -f "$REPO_DIR/bin/macshell-sync-upstream" ] && install -m 755 "$REPO_DIR/bin/macshell-sync-upstream" "${HOME}/.local/bin/macshell-sync-upstream"
[ -f "$REPO_DIR/MacShell/assets/spatial-sofa.conf" ] && install -m 644 "$REPO_DIR/MacShell/assets/spatial-sofa.conf" "${HOME}/.config/macshell/spatial-sofa.conf"
[ -f "$REPO_DIR/MacShell/assets/macshell-earbuds-sync.service" ] && install -m 644 "$REPO_DIR/MacShell/assets/macshell-earbuds-sync.service" "${HOME}/.config/systemd/user/macshell-earbuds-sync.service"
[ -f "$REPO_DIR/config/systemd/macshell.service" ] && install -m 644 "$REPO_DIR/config/systemd/macshell.service" "${HOME}/.config/systemd/user/macshell.service"
log_ok "Installed helper tools and utilities into ~/.local/bin"

# Ensure ~/.local/bin is in PATH for future shells
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# 8. Configure Systemd Services & Timers
log_step "Enabling automated services and timers..."
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now macshell-update.timer 2>/dev/null || true
systemctl --user enable --now macshell-earbuds-sync.service 2>/dev/null || true
systemctl --user enable --now macshell.service 2>/dev/null || true
log_ok "Services and timers active"

# 9. Reload Hyprland and Start Shell
log_step "Finalizing and starting session..."
if have hyprctl && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hyprctl reload >/dev/null 2>&1 || true
    log_ok "Hyprland reloaded"
fi

# Restart QuickShell MacShell cleanly
if pgrep -f "qs -c MacShell" >/dev/null 2>&1; then
    log_info "Reloading active QuickShell session..."
    killall qs 2>/dev/null || true
    sleep 0.5
fi
sh "${HOME}/.local/bin/macshell-start" >/dev/null 2>&1 &
log_ok "MacShell started"

echo ""
printf "%s%s========================================================================%s\n" "$BOLD" "$GREEN" "$RESET"
printf "%s%s✓ MacShell & MacLock installation complete!%s\n" "$BOLD" "$GREEN" "$RESET"
printf "%s%s========================================================================%s\n" "$BOLD" "$GREEN" "$RESET"
echo ""
echo "Key shortcuts configured:"
echo "  • SUPER + Space        : Spotlight Search"
echo "  • SUPER + Z            : MacShell Settings & Hub"
echo "  • SUPER + D            : MacShell Whiteboard"
echo "  • SUPER + C            : Instant Clear Whiteboard"
echo "  • SUPER + V            : Spotlight Clipboard History"
echo "  • SUPER + .            : Emoji Picker"
echo "  • SUPER + L            : MacLock Lock Screen"
echo "  • ALT + F1 / F2 / F3   : Fullscreen / Region Screenshot / Screen Record"
echo "  • SUPER + SHIFT + V    : Toggle Window Float"
echo "  • SUPER + R            : Spotlight App Launcher"
echo ""
echo "How future updates work:"
echo "  1. Automatic Daily Updates: macshell-update pulls the latest commits from your fork."
echo "  2. Syncing Upstream Releases: Whenever the original creator (0-ss) pushes updates,"
echo "     simply run:"
echo "       ${CYAN}macshell-sync-upstream${RESET}"
echo "     This fetches 0-ss/MacShell, cleanly 3-way merges their new features on top of"
echo "     your custom Hub, Bento, and Equalizer, and deploys it live with zero conflicts!"
echo ""
