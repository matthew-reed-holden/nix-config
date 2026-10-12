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
# The directory is currently empty (the spicetify hook this recipe was
# written for was never committed), so nullglob keeps `just up` from
# dying on an unmatched glob.
# Idempotent — `install -m 644` overwrites cleanly.
install-pacman-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    for hook in etc/pacman.d/hooks/*.hook; do
        echo "Installing $(basename "$hook")..."
        sudo install -Dm644 "$hook" "/etc/pacman.d/hooks/$(basename "$hook")"
    done

# Restarts postgres only when something changed (shared_preload_libraries
# and listen_addresses need a full restart, not a reload).
# Install etc/postgresql/ to /etc/postgresql/ and point postgres at it.
install-postgres-config:
    #!/usr/bin/env bash
    set -euo pipefail
    conf=/var/lib/postgres/data/postgresql.conf
    if ! sudo test -f "$conf"; then
        echo "No postgres cluster at $conf — initdb first, then re-run." >&2
        exit 0
    fi
    changed=0
    for f in conf.d/shadowfax.conf pg_hba.conf; do
        if ! sudo cmp -s "etc/postgresql/$f" "/etc/postgresql/$f"; then
            echo "Installing /etc/postgresql/$f..."
            sudo install -Dm644 "etc/postgresql/$f" "/etc/postgresql/$f"
            changed=1
        fi
    done
    line="include_dir = '/etc/postgresql/conf.d'"
    if ! sudo grep -qxF "$line" "$conf"; then
        echo "$line" | sudo tee -a "$conf" >/dev/null
        changed=1
    fi
    if [ "$changed" = 1 ]; then
        sudo systemctl restart postgresql
    fi

# Install the ollama.service drop-in under etc/systemd/ and restart Ollama if it changed.
install-ollama-config:
    #!/usr/bin/env bash
    set -euo pipefail
    f=systemd/system/ollama.service.d/override.conf
    if ! sudo cmp -s "etc/$f" "/etc/$f"; then
        echo "Installing /etc/$f..."
        sudo install -Dm644 "etc/$f" "/etc/$f"
        sudo systemctl daemon-reload
        sudo systemctl restart ollama
    fi

# Full bootstrap: install packages, pacman hooks, postgres and ollama config, then activate.
up: install-deps install-pacman-hooks install-postgres-config install-ollama-config switch
