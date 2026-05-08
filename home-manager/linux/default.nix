# Linux home-manager entrypoint.
#
# Intentionally minimal: the starting point for gradually migrating
# user-space on Arch (and other non-NixOS Linux hosts) to Nix. Each
# addition goes in with a reason, not by bulk-importing from Darwin.
{
  config,
  inputs,
  lib,
  stateVersion,
  ...
}:
{
  imports = [
    ../../lib/noughty
    inputs.sops-nix.homeManagerModules.sops
  ];

  home = {
    inherit stateVersion;
    username = config.noughty.user.name;
    homeDirectory = "/home/${config.noughty.user.name}";
    sessionPath = [ "$HOME/.local/bin" ];
    # Point SSH (and ssh-keygen, used by git for SSH commit signing) at
    # the 1Password agent socket. Without this set, git -S / ssh-add
    # can't find the agent despite ~/.ssh/config's IdentityAgent hint,
    # because ssh-keygen doesn't read ssh_config.
    sessionVariables = {
      SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };

  programs.home-manager.enable = true;

  # Pattern 3 for zsh: programs.zsh.package isn't nullable (same trap as
  # starship), so hand-write .zsh{env,rc} to keep pacman's /usr/bin/zsh
  # authoritative.

  # .zshenv runs on every zsh invocation (login, non-login, interactive,
  # non-interactive). Home-manager normally wires session vars through
  # ~/.profile when programs.bash is enabled; with bash removed we have
  # to source hm-session-vars.sh ourselves or PATH / LOCALE_ARCHIVE are
  # missing in fresh shells.
  home.file.".zshenv".text = ''
    . ${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh
  '';

  home.file.".zshrc".text = ''
    # Themed LS_COLORS via vivid (Catppuccin Mocha). Propagates
    # automatically to ls, fd, eza, tree, and anything else that
    # reads LS_COLORS. No-op if vivid isn't installed yet (fresh
    # machine before `just install-deps`).
    if command -v vivid >/dev/null 2>&1; then
      export LS_COLORS="$(vivid generate catppuccin-mocha)"
    fi

    # History — keeping ~/.histfile so existing command history persists.
    # Sizes bumped to match darwin (save=10000). Options mirror darwin's
    # programs.zsh.history: append (don't clobber), extended (timestamps
    # in histfile), dedup aggressively.
    HISTFILE=~/.histfile
    HISTSIZE=10000
    SAVEHIST=10000
    setopt APPEND_HISTORY          # append rather than overwrite histfile
    setopt EXTENDED_HISTORY        # save timestamps alongside commands
    setopt HIST_EXPIRE_DUPS_FIRST  # expire dupes first when trimming
    setopt HIST_IGNORE_ALL_DUPS    # drop older dupes when adding a new one

    # autocd — typing a directory name alone cd's into it
    # (e.g. `Documents/foo` at the prompt, no `cd` needed). Mirrors
    # darwin's programs.zsh.autocd = true.
    setopt AUTO_CD

    bindkey -e

    # Completion (pacman's /usr/share/zsh/site-functions is on FPATH by default)
    autoload -Uz compinit
    compinit

    # NVM ships bash-style completion — enable bash-compat in zsh. Must
    # follow compinit.
    autoload -U +X bashcompinit
    bashcompinit

    # eza replaces ls — pattern 3 (skipping programs.eza because its
    # only useful output is the zsh alias, which the module gates on
    # programs.zsh.enable = true). Flags mirror darwin: group dirs
    # first, show column headers, git status column, icons when tty.
    alias ls='eza --group-directories-first --header --git --icons=auto'
    alias grep='grep --color=auto'
    # Pacman ships Zed as `zeditor` (the `zed` name is taken in core by
    # an old line editor). Keep muscle memory.
    alias zed='zeditor'

    # Ghostty shell integration (no-op outside ghostty)
    if [[ -n "''${GHOSTTY_RESOURCES_DIR}" ]]; then
      builtin source "''${GHOSTTY_RESOURCES_DIR}/shell-integration/zsh/ghostty-integration"
    fi

    # NVM (pacman 0.40.4 at /usr/share/nvm/)
    . /usr/share/nvm/init-nvm.sh

    # zoxide — hand-wired (programs.zoxide.package isn't nullable, and
    # its shell integration gates on programs.zsh.enable which we don't
    # use). --cmd cd replaces the builtin so `cd proj` jumps by
    # frecency; `cdi` opens an interactive picker; plain paths still
    # work as normal cd input.
    eval "$(/usr/bin/zoxide init zsh --cmd cd)"

    eval "$(/usr/bin/starship init zsh)"

    # fzf — key bindings (Ctrl+R history, Ctrl+T file paste, Alt+C cd)
    # and tab completion. Uses fd as the finder; hidden files included;
    # cwd prefix stripped for cleaner paths. FZF_DEFAULT_OPTS sets
    # Catppuccin Mocha colors (mirror of catppuccin/fzf mocha theme).
    export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --strip-cwd-prefix --hidden'
    export FZF_DEFAULT_OPTS="\
    --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
    --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
    --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
    --color=selected-bg:#45475a \
    --color=border:#6c7086,label:#cdd6f4"
    eval "$(fzf --zsh)"

    # zsh-autosuggestions (pacman). Registers zle widgets used below.
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

    # Catppuccin Mocha theme for syntax-highlighting — sets
    # ZSH_HIGHLIGHT_HIGHLIGHTERS and ZSH_HIGHLIGHT_STYLES. Must come
    # BEFORE the main plugin or the styles are ignored.
    source ${config.xdg.configHome}/zsh/catppuccin-mocha.zsh

    # zsh-syntax-highlighting (pacman). Wraps every zle widget defined
    # up to this point — so it comes AFTER autosuggestions but BEFORE
    # history-substring-search (the opposite of our old "last" rule).
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

    # zsh-history-substring-search (pacman). Must be sourced AFTER
    # syntax-highlighting per upstream docs — otherwise the highlighter
    # overwrites the Up/Down keybindings. Arrow-bindings use emacs-mode
    # escape sequences (bindkey -e above).
    source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down

    # Source MCP secrets if sops has decrypted them. File is generated
    # by home-manager (see home.file.".zshrc.mcp-secrets" below); cats
    # the sops-decrypted paths into env vars for any shell tool that
    # reads them.
    [ -f "$HOME/.zshrc.mcp-secrets" ] && source "$HOME/.zshrc.mcp-secrets"
  '';

  # Pattern 3 for starship: programs.starship would install nix's starship
  # alongside pacman's (its package option isn't nullable). Hand-wire it
  # instead — config file via xdg, init via .zshrc above.
  xdg.configFile."starship.toml".source = ./starship.toml;

  # Catppuccin Mocha theme for zsh-syntax-highlighting. The plugin
  # modules (programs.zsh.autosuggestion / .syntaxHighlighting) aren't
  # usable here: they're sub-options of programs.zsh (which we can't
  # enable without installing a duplicate zsh), hardcode nix packages,
  # and autosuggestion has no package option at all. Pattern 3 — drop
  # the theme into ~/.config/zsh/ and source it from .zshrc.
  xdg.configFile."zsh/catppuccin-mocha.zsh".source =
    ./zsh-syntax-highlighting-catppuccin-mocha.zsh;

  # Git — pattern 3 (programs.git.package isn't nullable). Identity,
  # modern defaults, and SSH commit signing via 1Password's agent using
  # id_github. HTTPS credential helper (1Password CLI) TBD — add when
  # the op:// path for a GitHub PAT is confirmed.
  xdg.configFile."git/config".source = ./gitconfig;

  # Allowed signers for `git log --show-signature` verification.
  xdg.configFile."git/allowed_signers".source = ./git-allowed-signers;

  # bat — pattern 3 (programs.bat.package isn't nullable). Config
  # mirrors darwin (--style=plain) plus the Catppuccin Mocha theme
  # file dropped into ~/.config/bat/themes/. bat needs `bat cache
  # --build` after a theme file lands to make the name resolvable —
  # handled by the activation hook below.
  xdg.configFile."bat/config".source = ./batconfig;
  xdg.configFile."bat/themes/Catppuccin Mocha.tmTheme".source =
    ./bat-catppuccin-mocha.tmTheme;

  # ripgrep — pattern 2 (module's `package` option IS nullable, unlike
  # bat / starship / zsh / git / waybar). Mirrors darwin's arguments
  # list. The module writes ~/.config/ripgrep/ripgreprc and exports
  # RIPGREP_CONFIG_PATH via home.sessionVariables, which our .zshenv
  # sources.
  programs.ripgrep = {
    enable = true;
    package = null;
    arguments = [
      "--colors=line:style:bold"
      "--max-columns-preview"
      "--smart-case"
    ];
  };

  # fd — pattern 2. Darwin enables it bare; same here. The module
  # doesn't write any files when `ignores` is empty, so this is
  # mostly a declaration of intent, and it lets programs.fzf (later)
  # pick fd as its default finder automatically.
  programs.fd = {
    enable = true;
    package = null;
  };

  # jq — pattern 2 bare enable. No settings needed; mirrors darwin.
  programs.jq = {
    enable = true;
    package = null;
  };

  # Docker credsStore -> "secretservice" (KWallet via libsecret). The
  # config.json is mutable (rewritten by `docker login`), so we patch
  # one key with jq instead of owning the whole file. Skips cleanly if
  # the file or jq don't exist yet (fresh machine pre-`just install-deps`).
  home.activation.dockerCredsStore =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -f "$HOME/.docker/config.json" ] && [ -x /usr/bin/jq ]; then
        tmp=$(mktemp)
        /usr/bin/jq '.credsStore = "secretservice"' \
          "$HOME/.docker/config.json" > "$tmp" \
          && mv "$tmp" "$HOME/.docker/config.json"
      fi
    '';

  # lazygit — pattern 3. Skipping programs.lazygit.settings because
  # the theme file is easier to edit as YAML than as a Nix attrset,
  # and matches how we handle other catppuccin-mocha theme files
  # (starship, bat, zsh-syntax-highlighting). Mauve accent matches
  # our zsh-syntax-highlighting command color.
  xdg.configFile."lazygit/config.yml".source = ./lazygit.yml;

  # gh — pattern 3, but via `gh config set` instead of xdg.configFile.
  # gh writes to its own config.yml during `auth login` etc., so a
  # read-only Nix-store symlink breaks it (permission denied). Set
  # values via the activation hook instead — values stay declarative,
  # file stays user-writable for gh to update auth/hosts.
  #
  # Also installs gh extensions:
  #   dlvhdr/gh-dash    — GitHub PR/issue dashboard (`gh dash`)
  #   dlvhdr/gh-enhance — GitHub Actions TUI (`gh enhance`)
  # `--force` is idempotent: no-op when already at latest, upgrade
  # otherwise. gh-dash's config lives at ~/.config/gh-dash/config.yml
  # (see below). gh-enhance has no config to theme.
  home.activation.ghConfig =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Absolute path because activation PATH doesn't include /usr/bin
      # in standalone home-manager. The -x check keeps this safe on
      # fresh machines where pacman hasn't installed gh yet.
      if [ -x /usr/bin/gh ]; then
        run /usr/bin/gh config set git_protocol ssh
        run /usr/bin/gh config set editor nvim
        run /usr/bin/gh config set prompt enabled
        run /usr/bin/gh extension install --force dlvhdr/gh-dash
        run /usr/bin/gh extension install --force dlvhdr/gh-enhance
      fi
    '';

  # gh-dash theme (Catppuccin Mocha, mauve). gh-dash reads its config
  # but doesn't rewrite it, so xdg.configFile is safe here.
  xdg.configFile."gh-dash/config.yml".source = ./gh-dash.yml;

  # Zed — pattern 2 (module is nullable). package = null keeps pacman's
  # /usr/bin/zeditor authoritative (note: pacman names the binary
  # `zeditor`, not `zed`, because `zed` is already taken in core by an
  # old line editor; our zshrc aliases zed -> zeditor).
  #
  # Theme set in userSettings so we don't need inputs.catppuccin's
  # home-module (which darwin imports); the catppuccin extension below
  # provides the palette.
  #
  # ~/.config/zed/settings.json is written as a read-only symlink into
  # the Nix store — UI-driven settings changes won't persist. Edit Nix
  # config + switch to change settings.
  programs.zed-editor = {
    enable = true;
    package = null;
    extensions = [
      "ansible"
      "catppuccin"
      "catppuccin-icons"
      "dockerfile"
      "editorconfig"
      "git-firefly"
      "graphql"
      "helm"
      "justfile"
      "make"
      "nix"
      "proto"
      "scss"
      "sql"
      "terraform"
      "toml"
    ];
    userSettings = {
      auto_update = false;
      base_keymap = "VSCode";
      theme = "Catppuccin Mocha";
      buffer_font_family = "FiraCode Nerd Font Mono";
      buffer_font_size = 12;
      buffer_font_weight = 400;
      ui_font_family = "Work Sans";
      ui_font_size = 16;
      ui_font_weight = 400;
      agent_buffer_font_size = 12;
      agent_ui_font_size = 13;
      cursor_shape = "block";
      tab_size = 2;
      telemetry = {
        diagnostics = false;
        metrics = false;
      };
      terminal = {
        copy_on_select = true;
        cursor_shape = "block";
        font_family = "FiraCode Nerd Font Mono";
        font_size = 13;
      };
    };
  };

  # Rebuild bat's theme index after linkGeneration places the symlink.
  # No-op if bat isn't on PATH yet (pacman install pending on a fresh
  # machine), so the hook is safe to run unconditionally.
  home.activation.batCacheBuild =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if command -v bat >/dev/null 2>&1; then
        run bat cache --build > /dev/null 2>&1 || true
      fi
    '';

  # Waybar — pattern 3 (programs.waybar.package isn't nullable). Step 1:
  # scaffolding + clock, catppuccin-mocha palette. See waybar/ for files.
  # Targets Hyprland long-term; fine to iterate on KDE in the meantime
  # (waybar will draw on top of the Plasma panel).
  xdg.configFile."waybar/config.jsonc".source = ./waybar/config.jsonc;
  xdg.configFile."waybar/style.css".source    = ./waybar/style.css;
  xdg.configFile."waybar/mocha.css".source    = ./waybar/mocha.css;

  # Hyprland — main config + per-section modular splits under conf/.
  # ML4W-style: each topic (monitors, input, decoration, keybinds, ...)
  # lives in its own file, sourced from hyprland.conf via `source =`.
  # hyprctl tweaks don't write back, so read-only symlinks are fine.
  xdg.configFile."hypr/hyprland.conf".source         = ./hypr/hyprland.conf;
  xdg.configFile."hypr/conf/monitors.conf".source    = ./hypr/conf/monitors.conf;
  xdg.configFile."hypr/conf/environment.conf".source = ./hypr/conf/environment.conf;
  xdg.configFile."hypr/conf/input.conf".source       = ./hypr/conf/input.conf;
  xdg.configFile."hypr/conf/general.conf".source     = ./hypr/conf/general.conf;
  xdg.configFile."hypr/conf/decoration.conf".source  = ./hypr/conf/decoration.conf;
  xdg.configFile."hypr/conf/animations.conf".source  = ./hypr/conf/animations.conf;
  xdg.configFile."hypr/conf/layouts.conf".source     = ./hypr/conf/layouts.conf;
  xdg.configFile."hypr/conf/misc.conf".source        = ./hypr/conf/misc.conf;
  xdg.configFile."hypr/conf/windowrules.conf".source = ./hypr/conf/windowrules.conf;
  xdg.configFile."hypr/conf/keybindings.conf".source = ./hypr/conf/keybindings.conf;
  xdg.configFile."hypr/conf/autostart.conf".source   = ./hypr/conf/autostart.conf;
  xdg.configFile."hypr/hyprlock.conf".source         = ./hypr/hyprlock.conf;
  xdg.configFile."hypr/hypridle.conf".source         = ./hypr/hypridle.conf;

  # Rofi — ML4W-style behavior + colors.rasi (Catppuccin Mocha + M3
  # aliases so ML4W widget layouts drop in unchanged).
  xdg.configFile."rofi/config.rasi".source         = ./rofi/config.rasi;
  xdg.configFile."rofi/config-compact.rasi".source  = ./rofi/config-compact.rasi;
  xdg.configFile."rofi/config-cliphist.rasi".source   = ./rofi/config-cliphist.rasi;
  xdg.configFile."rofi/config-short.rasi".source      = ./rofi/config-short.rasi;
  xdg.configFile."rofi/config-screenshot.rasi".source = ./rofi/config-screenshot.rasi;
  xdg.configFile."rofi/config-ocr-lang.rasi".source   = ./rofi/config-ocr-lang.rasi;

  # Catppuccin flavor variants. Active palette at
  # ~/.config/rofi/colors.rasi is user-mutable (not Nix-managed) so
  # select-flavor.sh can swap it at runtime.
  xdg.configFile."rofi/themes/latte.rasi".source     = ./rofi/themes/latte.rasi;
  xdg.configFile."rofi/themes/frappe.rasi".source    = ./rofi/themes/frappe.rasi;
  xdg.configFile."rofi/themes/macchiato.rasi".source = ./rofi/themes/macchiato.rasi;
  xdg.configFile."rofi/themes/mocha.rasi".source     = ./rofi/themes/mocha.rasi;

  # Seed colors.rasi from mocha when missing — fresh-machine bootstrap.
  # Once matugen runs (via select-wallpaper.sh), this gets overwritten
  # with wallpaper-derived palette.
  home.activation.rofiFlavorSeed =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ ! -e "$HOME/.config/rofi/colors.rasi" ]; then
        cp "$HOME/.config/rofi/themes/mocha.rasi" "$HOME/.config/rofi/colors.rasi"
      fi
    '';

  # matugen — wallpaper-derived M3 color palettes. Invoked by
  # select-wallpaper.sh; templates regenerate on each wallpaper change.
  xdg.configFile."matugen/config.toml".source                       = ./matugen/config.toml;
  xdg.configFile."matugen/templates/rofi-colors.rasi".source        = ./matugen/templates/rofi-colors.rasi;
  xdg.configFile."matugen/templates/colors.css".source              = ./matugen/templates/colors.css;
  xdg.configFile."matugen/templates/gtk-colors.css".source          = ./matugen/templates/gtk-colors.css;
  xdg.configFile."matugen/templates/btop.theme".source              = ./matugen/templates/btop.theme;

  # Browser flags — Wayland-native rendering for Brave/Chromium/Edge.
  xdg.configFile."chromium-flags.conf".source = ./browser-flags/chromium-flags.conf;
  xdg.configFile."edge-flags.conf".source     = ./browser-flags/chromium-flags.conf;

  # GTK 3 + 4 — gtk.css imports matugen-generated colors.css.
  # settings.ini sets theme/icon/cursor names.
  xdg.configFile."gtk-3.0/gtk.css".source      = ./gtk/gtk.css;
  xdg.configFile."gtk-3.0/settings.ini".source = ./gtk/settings.ini;
  xdg.configFile."gtk-4.0/gtk.css".source      = ./gtk/gtk.css;
  xdg.configFile."gtk-4.0/settings.ini".source = ./gtk/settings.ini;

  # qt6ct + xsettingsd + fastfetch + wlogout configs.
  xdg.configFile."qt6ct/qt6ct.conf".source        = ./qt6ct/qt6ct.conf;
  xdg.configFile."xsettingsd/xsettingsd.conf".source = ./xsettingsd/xsettingsd.conf;
  xdg.configFile."fastfetch/config.jsonc".source  = ./fastfetch/config.jsonc;
  xdg.configFile."wlogout/layout".source          = ./wlogout/layout;
  xdg.configFile."wlogout/style.css".source       = ./wlogout/style.css;

  # .Xresources — legacy XWayland palette.
  home.file.".Xresources".source = ./Xresources/.Xresources;

  # Seed empty matugen-output files so @import doesn't error pre-matugen.
  home.activation.gtkColorsSeed =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      for d in gtk-3.0 gtk-4.0; do
        f="$HOME/.config/$d/colors.css"
        [ -e "$f" ] || : > "$f"
      done
      mkdir -p "$HOME/.config/btop/themes"
      [ -e "$HOME/.config/btop/themes/matugen.theme" ] || : > "$HOME/.config/btop/themes/matugen.theme"
    '';

  # Seed empty waybar colors.css so style.css's @import doesn't error
  # before first matugen run.
  home.activation.waybarColorsSeed =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ ! -e "$HOME/.config/waybar/colors.css" ]; then
        : > "$HOME/.config/waybar/colors.css"
      fi
    '';

  # swaync — notification daemon + control center.
  xdg.configFile."swaync/config.json".source   = ./swaync/config.json;
  xdg.configFile."swaync/style.css".source     = ./swaync/style.css;
  xdg.configFile."swaync/fallback.css".source  = ./swaync/fallback.css;

  # Seed empty swaync colors.css so style.css's @import doesn't error
  # before first matugen run.
  home.activation.swayncColorsSeed =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ ! -e "$HOME/.config/swaync/colors.css" ]; then
        : > "$HOME/.config/swaync/colors.css"
      fi
    '';

  # Spicetify — Catppuccin theme. Theme files (color.ini + user.css) are
  # static, so symlinks via xdg.configFile are fine. config-xpui.ini is
  # spicetify's mutable config (rewritten by `spicetify config <k> <v>`),
  # so it's set via activation hook instead — same pattern as gh.
  #
  # /opt/spotify must be user-writable for `spicetify backup apply` to
  # work (spicetify patches Spotify's xpui.spa in place). One-time fix:
  #   sudo chmod a+wr /opt/spotify -R
  #   sudo chmod a+wr /opt/spotify/Apps -R
  # Then run `spicetify backup apply` once.
  xdg.configFile."spicetify/Themes/catppuccin/color.ini".source = ./spicetify/color.ini;
  xdg.configFile."spicetify/Themes/catppuccin/user.css".source  = ./spicetify/user.css;

  home.activation.spicetifyConfig =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -x /usr/bin/spicetify ]; then
        run /usr/bin/spicetify config current_theme catppuccin
        run /usr/bin/spicetify config color_scheme mocha
      fi
    '';

  # Toggle helper for the Plasma global shortcut (Meta+Shift+B). Starts
  # waybar if not running, otherwise sends SIGUSR1 to toggle visibility.
  # Placed on PATH via ~/.local/bin (already in home.sessionPath). Kept
  # with a .sh suffix because Plasma 6's global-shortcut runner rejects
  # extensionless commands ("needs to be a .sh/.bash/.zsh/..." error).
  home.file.".local/bin/toggle-waybar.sh" = {
    source = ./waybar/toggle-waybar.sh;
    executable = true;
  };

  # Wallpaper picker — rofi-driven thumbnail menu, awww-applied with a
  # wipe transition. Wallpapers live at ~/Pictures/wallpapers (overridable
  # via WALLPAPER_DIR env). Bound to Super+Shift+W in keybindings.conf.
  home.file.".local/bin/select-wallpaper.sh" = {
    source = ./hypr/scripts/select-wallpaper.sh;
    executable = true;
  };

home.file.".local/bin/select-flavor.sh" = {
    source = ./hypr/scripts/select-flavor.sh;
    executable = true;
  };

  home.file.".local/bin/power-menu.sh" = {
    source = ./hypr/scripts/power-menu.sh;
    executable = true;
  };

  home.file.".local/bin/screenshot.sh" = {
    source = ./hypr/scripts/screenshot.sh;
    executable = true;
  };

  home.file.".local/bin/ocr.sh" = {
    source = ./hypr/scripts/ocr.sh;
    executable = true;
  };

  home.file.".local/bin/keybinds.sh" = {
    source = ./hypr/scripts/keybinds.sh;
    executable = true;
  };

  home.file.".local/bin/keybinds-mode.sh" = {
    source = ./hypr/scripts/keybinds-mode.sh;
    executable = true;
  };

  programs.ghostty = {
    enable = true;
    package = null;
    systemd.enable = false;
    settings = {
      theme = "Catppuccin Mocha";
      font-size = 10;
      shell-integration = "detect";
      shell-integration-features = "cursor,sudo,title,path";
    };
  };

  # ── sops-nix: decrypt MCP server tokens at activation ────────────────
  # Bootstrap on a fresh shadowfax (one-time, manual — keys aren't
  # checked into the repo):
  #   1. age-keygen -o ~/.config/sops/age/keys.txt
  #   2. add the public key (printed by age-keygen) to .sops.yaml as a
  #      new anchor (e.g. &user_shadowfax) and append it under the
  #      creation_rules age list
  #   3. sops updatekeys secrets/mcp.yaml   # re-encrypts to include
  #                                         # the new recipient
  # After bootstrap, each `home-manager switch` decrypts the secrets to
  # /run/user/$UID/secrets/<name> (mode 400, tmpfs, gone on reboot).
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ../../secrets/mcp.yaml;
    defaultSopsFormat = "yaml";

    secrets = {
      CONTEXT7_API_KEY = { };
      FIRECRAWL_API_KEY = { };
      GITHUB_PERSONAL_ACCESS_TOKEN = { };
      JINA_API_KEY = { };
    };
  };

  # ── Claude Code MCP servers ──────────────────────────────────────────
  # Claude Code is installed via npm (~/.local/bin/claude); only its
  # config is managed here. ~/.claude.json is mutable (Claude rewrites
  # session/state keys on every launch), so a Nix-store symlink would
  # break it. Instead, jq-merge the `mcpServers` key — same pattern as
  # dockerCredsStore above.
  #
  # Tokens are inlined from sops at activation time. ~/.claude.json is
  # already chmod 600. Skipped: mcp-nixos (Python/Nix-only; not on AUR)
  # — add later via uvx or nix store path if needed.
  #
  # `command = "npx"` resolves via PATH at MCP-server spawn time. Claude
  # inherits PATH from the shell that launched it, so npm/nvm/node must
  # be on PATH (already wired in .zshrc above).
  home.activation.claudeMcpConfig =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -f "$HOME/.claude.json" ] && [ -x /usr/bin/jq ]; then
        ctx7=$(cat ${config.sops.secrets.CONTEXT7_API_KEY.path} 2>/dev/null || echo "")
        firecrawl=$(cat ${config.sops.secrets.FIRECRAWL_API_KEY.path} 2>/dev/null || echo "")
        ghpat=$(cat ${config.sops.secrets.GITHUB_PERSONAL_ACCESS_TOKEN.path} 2>/dev/null || echo "")
        jina=$(cat ${config.sops.secrets.JINA_API_KEY.path} 2>/dev/null || echo "")

        tmp=$(mktemp)
        /usr/bin/jq \
          --arg ctx7 "$ctx7" \
          --arg firecrawl "$firecrawl" \
          --arg ghpat "$ghpat" \
          --arg jina "$jina" \
          '.mcpServers = {
            cloudflare:           { type: "sse",  url: "https://docs.mcp.cloudflare.com/mcp" },
            exa:                  { type: "sse",  url: "https://mcp.exa.ai/mcp" },
            "next-devtools":      { type: "stdio", command: "npx", args: ["-y", "next-devtools-mcp@latest"] },
            "chrome-devtools":    { type: "stdio", command: "npx", args: ["-y", "chrome-devtools-mcp@latest", "--no-usage-statistics"] },
            playwright:           { type: "stdio", command: "npx", args: ["-y", "@playwright/mcp@latest"] },
            "sequential-thinking":{ type: "stdio", command: "npx", args: ["-y", "@modelcontextprotocol/server-sequential-thinking"] },
            postgres:             { type: "stdio", command: "npx", args: ["-y", "@modelcontextprotocol/server-postgres"], env: { POSTGRES_CONNECTION_STRING: (env.POSTGRES_CONNECTION_STRING // "") } },
            github:               { type: "stdio", command: "npx", args: ["-y", "@modelcontextprotocol/server-github"], env: { GITHUB_PERSONAL_ACCESS_TOKEN: $ghpat } },
            firecrawl:            { type: "stdio", command: "npx", args: ["-y", "firecrawl-mcp"], env: { FIRECRAWL_API_KEY: $firecrawl } },
            context7:             { type: "sse",  url: "https://mcp.context7.com/mcp", headers: { Authorization: ("Bearer " + $ctx7) } },
            jina:                 { type: "sse",  url: "https://mcp.jina.ai/v1?exclude_tools=deduplicate_strings,expand_query,parallel_search_arxiv,parallel_search_ssrn,parallel_search_web,show_api_key,search_arxiv,search_jina_blog,search_ssrn,search_web", headers: { Authorization: ("Bearer " + $jina) } }
          }' \
          "$HOME/.claude.json" > "$tmp" \
          && mv "$tmp" "$HOME/.claude.json" \
          && chmod 600 "$HOME/.claude.json"
      fi
    '';

  # Export MCP secrets as env vars for shell scripts / agents that read
  # them outside Claude Code. Sourced from sops paths each shell start;
  # silently empty if sops hasn't decrypted yet (fresh-machine pre-bootstrap).
  home.file.".zshrc.mcp-secrets".text = ''
    export CONTEXT7_API_KEY=$(cat ${config.sops.secrets.CONTEXT7_API_KEY.path} 2>/dev/null || echo "")
    export FIRECRAWL_API_KEY=$(cat ${config.sops.secrets.FIRECRAWL_API_KEY.path} 2>/dev/null || echo "")
    export GITHUB_PERSONAL_ACCESS_TOKEN=$(cat ${config.sops.secrets.GITHUB_PERSONAL_ACCESS_TOKEN.path} 2>/dev/null || echo "")
    export JINA_API_KEY=$(cat ${config.sops.secrets.JINA_API_KEY.path} 2>/dev/null || echo "")
  '';
}
