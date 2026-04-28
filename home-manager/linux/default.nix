# Linux home-manager entrypoint.
#
# Intentionally minimal: the starting point for gradually migrating
# user-space on Arch (and other non-NixOS Linux hosts) to Nix. Each
# addition goes in with a reason, not by bulk-importing from Darwin.
{
  config,
  lib,
  stateVersion,
  ...
}:
{
  imports = [
    ../../lib/noughty
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
    sessionVariables.SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
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

  # Toggle helper for the Plasma global shortcut (Meta+Shift+B). Starts
  # waybar if not running, otherwise sends SIGUSR1 to toggle visibility.
  # Placed on PATH via ~/.local/bin (already in home.sessionPath). Kept
  # with a .sh suffix because Plasma 6's global-shortcut runner rejects
  # extensionless commands ("needs to be a .sh/.bash/.zsh/..." error).
  home.file.".local/bin/toggle-waybar.sh" = {
    source = ./waybar/toggle-waybar.sh;
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
}
