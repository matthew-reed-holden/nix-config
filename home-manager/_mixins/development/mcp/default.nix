{
  config,
  lib,
  noughtyLib,
  pkgs,
  ...
}:
let
  inherit (config.noughty) host;
  mcpSopsFile = ../../../../secrets/mcp.yaml;

  # Transform programs.mcp.servers into Zed's context_servers format
  # Stdio (flat): { name = { command = "cmd"; args = [...]; env = {...}; }; }
  # Remote: { name = { url = "..."; headers = {...}; }; }
  transformToZedContextServer = name: server:
    if server ? command then {
      name = name;
      value = {
        command = server.command;
        args = server.args or [ ];
      } // (lib.optionalAttrs (server ? env) { env = server.env; });
    } else if server ? url then {
      name = name;
      value = {
        url = server.url;
      } // (lib.optionalAttrs (server ? headers) { headers = server.headers; });
    } else
      null;

  zedContextServers =
    let
      transformed = lib.mapAttrsToList transformToZedContextServer config.programs.mcp.servers;
      filtered = builtins.filter (x: x != null) transformed;
    in
    lib.listToAttrs filtered;

  # Transform programs.mcp.servers into Copilot CLI's format
  # Copilot: { servers = { name = { type = "stdio"; command = "cmd"; args = [...]; env = {...}; }; }; }
  # Remote servers get wrapped via npx mcp-remote
  transformToCopilotServer = name: server:
    if server ? command then {
      name = name;
      value = {
        type = "stdio";
        command = server.command;
        args = server.args or [ ];
      } // (lib.optionalAttrs (server ? env) { env = server.env; });
    } else if server ? url then {
      name = name;
      value = {
        type = "stdio";
        command = "${pkgs.nodejs}/bin/npx";
        args = [ "-y" "mcp-remote" server.url ];
      };
    } else
      null;

  copilotMcpServers =
    let
      transformed = lib.mapAttrsToList transformToCopilotServer config.programs.mcp.servers;
      filtered = builtins.filter (x: x != null) transformed;
    in
    lib.listToAttrs filtered;
in
{
  config = lib.mkIf (noughtyLib.userHasTag "developer") {
    # ── Centralized MCP server definitions ────────────────────────────
    programs.mcp = {
      enable = true;
      servers = {
        # Cross-project only. Project servers (theostack API, postgres,
        # stripe, sentry, storybook, …) live in each repo's tracked .mcp.json.
        nixos = {
          command = "${pkgs.unstable.mcp-nixos}/bin/mcp-nixos";
        };
        chrome-devtools = {
          command = "${pkgs.nodejs}/bin/npx";
          args = [ "-y" "chrome-devtools-mcp@latest" "--no-usage-statistics" ];
        };
        playwright = {
          command = "${pkgs.nodejs}/bin/npx";
          args = [ "-y" "@playwright/mcp@latest" ];
        };
        # Secrets via {env:VAR}; the zsh init below exports them from sops.
        github = {
          command = "${pkgs.nodejs}/bin/npx";
          args = [ "-y" "@modelcontextprotocol/server-github" ];
          env = {
            GITHUB_PERSONAL_ACCESS_TOKEN = "{env:GITHUB_PERSONAL_ACCESS_TOKEN}";
          };
        };
        firecrawl = {
          command = "${pkgs.nodejs}/bin/npx";
          args = [ "-y" "firecrawl-mcp" ];
          env = {
            FIRECRAWL_API_KEY = "{env:FIRECRAWL_API_KEY}";
          };
        };
      };
    };

    # ── sops secrets ──────────────────────────────────────────────────
    sops = {
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      defaultSopsFile = mcpSopsFile;
      defaultSopsFormat = "yaml";

      secrets = {
        FIRECRAWL_API_KEY = { };
        GITHUB_PERSONAL_ACCESS_TOKEN = { };
        THEOSTACK_MCP_TOKEN = { };
      };
    };

    # ── Export secrets as env vars for agents ──────────────────────────
    programs.zsh.initContent = lib.mkOrder 600 ''
      # Export MCP secrets from sops
      export FIRECRAWL_API_KEY=$(cat ${config.sops.secrets.FIRECRAWL_API_KEY.path} 2>/dev/null || echo "")
      export GITHUB_PERSONAL_ACCESS_TOKEN=$(cat ${config.sops.secrets.GITHUB_PERSONAL_ACCESS_TOKEN.path} 2>/dev/null || echo "")
      export THEOSTACK_MCP_TOKEN=$(cat ${config.sops.secrets.THEOSTACK_MCP_TOKEN.path} 2>/dev/null || echo "")
    '';

    # ── OpenCode: uses enableMcpIntegration from programs.mcp ─────────
    programs.opencode.enableMcpIntegration = true;

    # ── Zed: inject context_servers for stdio MCP servers ─────────────
    programs.zed-editor = lib.mkIf config.programs.zed-editor.enable {
      userSettings = {
        context_servers = zedContextServers;
      };
    };

    # ── Copilot CLI: write mcp config file ────────────────────────────
    xdg.configFile."github-copilot/mcp.json".text = builtins.toJSON {
      mcpServers = copilotMcpServers;
    };
  };
}
