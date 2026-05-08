# Command runner for shadowfax bootstrap.
#
# Typical usage on an already-running machine:
#   just up             # install declared packages + activate home-manager
#
# First-time bootstrap on a fresh EndeavourOS install:
#   sudo pacman -S --needed --noconfirm just    # one-time: get this tool
#   just up                                       # everything else
#
# On vanilla Arch (no yay by default), install yay first:
#   git clone https://aur.archlinux.org/yay.git /tmp/yay
#   cd /tmp/yay && makepkg -si

default:
    @just --list --unsorted

# Yay is the AUR-aware pacman wrapper — official-repo packages are
# proxied to pacman, AUR packages are built via makepkg. --needed skips
# already-installed, so the recipe is idempotent.
#
# Install every package listed in packages.txt via yay.
install-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v yay >/dev/null 2>&1; then
        echo "yay not found — install it from AUR first:" >&2
        echo "  git clone https://aur.archlinux.org/yay.git /tmp/yay" >&2
        echo "  cd /tmp/yay && makepkg -si" >&2
        exit 1
    fi
    pkgs=$(grep -vE '^\s*(#|$)' packages.txt | awk '{print $1}' | tr '\n' ' ')
    echo "Installing / verifying $(echo "$pkgs" | wc -w) packages..."
    yay -S --needed --noconfirm $pkgs

# Activate the home-manager generation for shadowfax.
switch:
    nix run home-manager/release-25.11 -- switch --flake .#matthewholden@shadowfax

# Install pacman hooks under etc/pacman.d/hooks/ to /etc/pacman.d/hooks/.
# Currently: spicetify.hook (re-applies theme after Spotify upgrades).
# Idempotent — `install -m 644` overwrites cleanly.
install-pacman-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    for hook in etc/pacman.d/hooks/*.hook; do
        echo "Installing $(basename "$hook")..."
        sudo install -Dm644 "$hook" "/etc/pacman.d/hooks/$(basename "$hook")"
    done

# Full bootstrap: install packages, install pacman hooks, then activate.
up: install-deps install-pacman-hooks switch
