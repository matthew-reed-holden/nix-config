{
  catppuccinPalette,
  config,
  inputs,
  lib,
  noughtyLib,
  outputs,
  pkgs,
  stateVersion,
  ...
}:
let
  inherit (config.noughty) host;
  username = config.noughty.user.name;
  isLinux = host.is.linux;
  isDarwin = host.is.darwin;
in
{
  imports = [
    ../lib/noughty
    ./_mixins/development
    inputs.catppuccin.homeModules.catppuccin
    inputs.mac-app-util.homeManagerModules.default
    inputs.nix-index-database.homeModules.nix-index
    inputs.sops-nix.homeManagerModules.sops
  ];

  # sops-nix master needs go >= 1.26; stable nixpkgs ships 1.25. Drop once stable catches up.
  sops.package = (import inputs.sops-nix { pkgs = pkgs.unstable; }).sops-install-secrets;

  catppuccin = {
    inherit (catppuccinPalette) accent;
    inherit (catppuccinPalette) flavor;

    alacritty.enable = config.programs.alacritty.enable;
    bat.enable = config.programs.bat.enable;
    fish.enable = config.programs.fish.enable;
    fzf.enable = config.programs.fzf.enable;
    gh-dash.enable = config.programs.gh.extensions.gh-dash;
    ghostty.enable = config.programs.ghostty.enable;
    kitty.enable = true;
    micro.enable = config.programs.micro.enable;
    starship.enable = config.programs.starship.enable;
    yazi.enable = config.programs.yazi.enable;
    zsh-syntax-highlighting.enable = config.programs.zsh.enable;
  };

  # Disable copying apps to ~/Applications — requires App Management permission
  # which Jamf MDM keeps revoking on this managed machine.
  targets.darwin.copyApps.enable = lib.mkIf (username == "holdem3") false;

  xdg.enable = true;
  xdg.configHome = "/Users/${username}/.config";

  home = {
    inherit stateVersion;
    username = config.noughty.user.name;
    homeDirectory =
      if host.is.darwin then
        "/Users/${username}"
      else if noughtyLib.hostHasTag "lima" then
        "/home/${username}.linux"
      else
        "/home/${username}";

    enableNixpkgsReleaseCheck = true;

    file = {
      "${config.xdg.configHome}/fastfetch/config.jsonc".text =
        builtins.readFile ./_mixins/configs/fastfetch.jsonc;
      "${config.xdg.configHome}/borders/bordersrc".text = builtins.readFile ./_mixins/configs/bordersrc;
      "${config.xdg.configHome}/aerospace/aerospace.toml".text =
        builtins.readFile ./_mixins/configs/aerospace.toml;
      "${config.xdg.configHome}/yazi/keymap.toml".text =
        builtins.readFile ./_mixins/configs/yazi-keymap.toml;

      ".hidden".text = "snap";
      "${config.xdg.configHome}/sketchybar/sketchybarrc".text =
        builtins.readFile ./_mixins/configs/sketchybarrc;
    };

    # activation.installSketchyBarconfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    #   '';

    preferXdgDirectories = true;

    packages =
      with pkgs;
      [
        nerd-fonts.fira-code
        font-awesome
        noto-fonts-color-emoji
        noto-fonts-monochrome-emoji
        symbola
        work-sans
        cpufetch # Terminal CPU info
        fastfetch # Modern Unix system info
        ipfetch # Terminal IP info
        onefetch # Terminal git project info
        micro
        rustmission # Modern Unix Transmission client
        rsync # Copy files in style
        starship # Blazing fast rust powered shell prompt
      ]
      ++ lib.optionals isLinux [
        ramfetch
      ]
      ++ lib.optionals isDarwin [
        m-cli
        nh
        coreutils
      ];
    sessionVariables = {
      COLORTERM = "truecolor";
      EDITOR = "nvim";
      SYSTEMD_EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };

  fonts = {
    fontconfig = {
      enable = true;
      defaultFonts = {
        serif = [
          "Source Serif"
          "Noto Color Emoji"
        ];
        sansSerif = [
          "Work Sans"
          "Noto Color Emoji"
        ];
        monospace = [
          "FiraCode Nerd Font Mono"
          "Font Awesome 6 Free"
          "Font Awesome 6 Brands"
          "Symbola"
          "Noto Emoji"
        ];
        emoji = [
          "Noto Color Emoji"
        ];
      };
    };
  };

  # Workaround home-manager bug
  # - https://github.com/nix-community/home-manager/issues/2033
  news = {
    display = "silent";
  };

  nixpkgs = {
    overlays = [
      # Overlays defined via overlays/default.nix and pkgs/default.nix
      outputs.overlays.localPackages
      outputs.overlays.modifiedPackages
      outputs.overlays.unstablePackages
    ];
    # Configure your nixpkgs instance
    config = {
      allowUnfree = true;
    };
  };

  programs = {
    alacritty = {
      enable = true;
    };

    ghostty = {
      enable = true;
      package = if isDarwin then null else pkgs.ghostty;
      enableZshIntegration = true;
      settings = {
        shell-integration = "zsh";
        shell-integration-features = "cursor,sudo,title,path";
        term = "xterm-256color";
      };
    };

    bat = {
      enable = true;
      config = {
        style = "plain";
      };
    };

    dircolors = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      enableZshIntegration = true;
    };

    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    eza = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      enableZshIntegration = true;
      extraOptions = [
        "--group-directories-first"
        "--header"
      ];
      git = true;
      icons = "auto";
    };

    fd = {
      enable = true;
    };

    fzf = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableFishIntegration = true;
    };

    gh = {
      enable = true;
      extensions = with pkgs; [
        gh-dash
        gh-markdown-preview
      ];
      settings = {
        editor = "micro";
        git_protocol = "ssh";
        prompt = "enabled";
      };
    };

    home-manager.enable = true;

    jq.enable = true;

    kitty = {
      enable = true;
      shellIntegration.enableZshIntegration = true;
      font = {
        name = "Fira Code Mono";
        package = pkgs.nerd-fonts.fira-code;
        size = 10;
      };
      keybindings = {
        "kitty_mod+l" = "next_tab";
        "kitty_mod+h" = "previous_tab";
        "kitty_mod+m" = "toggle_layout stack";
        "kitty_mod+z" = "toggle_layout stack";
        "kitty_mod+enter" = "launch --location=split --cwd=current";
        "kitty_mod+v" = "launch --location=vsplit --cwd=current";
        "kitty_mod+minus" = "launch --location=hsplit --cwd=currentt";
        "kitty_mod+left" = "neighboring_window left";
        "kitty_mod+right" = "neighboring_window right";
        "kitty_mod+up" = "neighboring_window up";
        "kitty_mod+down" = "neighboring_window down";
        "kitty_mod+r" = "show_scrollback";
      };
      settings = {
        cursor_trail = 3;
        cursor = "none";
        kitty_mod = "cmd+shift";
        scrollback_lines = 10000;
        touch_scroll_multiplier = 2.0;
        copy_on_select = true;
        enable_audio_bell = false;
        remember_window_size = true;
        initial_window_width = 1600;
        initial_window_height = 1000;
        hide_window_decorations = true;
        tab_bar_style = "powerline";
        tab_separator = " ";
        enabled_layouts = "Splits,Stack";
        dynamic_background_opacity = true;
        tab_title_template = "{title}{fmt.bold}{'  ' if num_windows > 1 and layout_name == 'stack' else ''}";
      };
    };

    kubecolor = {
      enable = true;
      enableAlias = true;
    };

    lazygit = {
      enable = true;
    };

    nix-index.enable = true;

    ripgrep = {
      arguments = [
        "--colors=line:style:bold"
        "--max-columns-preview"
        "--smart-case"
      ];
      enable = true;
    };

    starship = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      # https://github.com/etrigan63/Catppuccin-starship
    };

    yazi = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      enableZshIntegration = true;
      shellWrapperName = "y";
      settings = {
        manager = {
          show_hidden = false;
          show_symlink = true;
          sort_by = "natural";
          sort_dir_first = true;
          sort_sensitive = false;
          sort_reverse = false;
        };
      };
    };

    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableFishIntegration = true;
      enableZshIntegration = true;
      # Replace cd with z and add cdi to access zi
      options = [ "--cmd cd" ];
    };

    vscode = {
      enable = true;
    };

    zsh = {
      autocd = true;
      autosuggestion = {
        enable = true;
      };
      completionInit = ''
        autoload -U compinit && compinit
      '';
      dotDir = "${config.xdg.configHome}/zsh";
      enable = true;
      enableCompletion = true;
      enableVteIntegration = true;
      envExtra = ''
        export DOTFILES="${config.xdg.configHome}"

        ### ASDF ####
        #############

        export ASDF_CONFIG_FILE="${config.xdg.configHome}/asdf/.asdfrc"


        ### JETBRAINS ###
        #################

        export FLEET_PROPERTIES_FILE="${config.xdg.configHome}/jetbrains/fleet/fleet.properties"

        ###### GO #######
        #################
        export GOPATH="$HOME/.go"

        ##### DOTNET #######
        ####################
        export DOTNET_ROOT="/usr/local/share/dotnet"
        export DOTNET_TOOLS="$DOTNET_ROOT/tools"

        #### NODE #######
        #################

        export ENV="$DOTFILES/pnpm"

        #### KUBE ######
        ###############
        export KUBECONFIG="$DOTFILES/kube/config"

      '';
      history = {
        append = true;
        expireDuplicatesFirst = true;
        extended = true;
        ignoreAllDups = true;
        ignoreDups = true;
        save = 10000;
      };
      historySubstringSearch = {
        enable = true;
      };
      # Extra commands that should be added to .zshrc before compinit.
      initContent = lib.mkOrder 550 ''
        ### HOMEBREW ###
        ################
        eval "$(/opt/homebrew/bin/brew shellenv)"

        ###### NVM ########
        ###################
         export NVM_DIR="$HOME/.nvm"
        [ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ] && \. "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" # This loads nvm
        [ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ] && \. "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" # This loads nvm bash_completion

        ###############
        ####JETBRAINS##

        export PATH="$PATH:$HOME/.jetbrains/bin"

        ####STREAMPIPES####
        ###################

        export PATH="$PATH:$HOME/Code/github/heisenbergoss/streampipes/installer/cli"

        ##### GOLANG #######
        ####################

        export PATH="$PATH:$GOPATH/bin"

        ##### DOTNET #######
        ####################
        export PATH="$PATH:$DOTNET_ROOT:$DOTNET_TOOLS"

      '';
      # Commands that should be added to top of .zshrc.
      initExtraFirst = "";
      # Extra commands that should be added to .zlogin.
      loginExtra = "";
      # Environment variables that will be set for zsh session.
      sessionVariables = {

      };
      # An attribute set that maps aliases (the top level attribute names in this option) to command strings or directly to build outputs.
      shellAliases = {

      };
      syntaxHighlighting = {
        enable = true;
      };

      zsh-abbr = {
        enable = true;
        abbreviations = { };
      };
    };
  };

}
