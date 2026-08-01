# The workbench system, independent of how it is deployed: imported both as the inner
# config of the `lani-shell` container and as a standalone system for the nspawn rootfs.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.lani;

  agentPackages = {
    pi = pkgs.pi-coding-agent;
    opencode = pkgs.opencode;
    claude = pkgs.claude-code;
  };

  selectedAgents = lib.filter (a: a != "shell") cfg.shell.agents;

  catalogPath = builtins.toString ../catalog;
in
{
  imports = [
    ./modules/options.nix
    ./agent-menu.nix
    ./web-terminal.nix
  ];

  config = lib.mkIf cfg.shell.enable {
    assertions = [
      {
        assertion = lib.elem "claude" cfg.shell.agents -> cfg.shell.enableClaudeCode;
        message = ''
          lani.shell.agents lists "claude" but lani.shell.enableClaudeCode is false.
          claude-code is unfree; enabling it is a licensing decision Lani will not make
          for you. Set lani.shell.enableClaudeCode = true, or drop "claude".
        '';
      }
    ];

    networking.hostName = lib.mkDefault "lani-shell";

    nixpkgs.config.allowUnfreePredicate =
      pkg: cfg.shell.enableClaudeCode && lib.getName pkg == "claude-code";

    services.openssh = {
      enable = true;
      ports = [ cfg.shell.sshPort ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    users.users.${cfg.user} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      home = "/home/${cfg.user}";
      # A LUKS home arrives bind-mounted already; recreating it would shadow the contents.
      createHome = lib.mkForce (!cfg.lukshome.enable);
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
      shell = pkgs.zsh;
    };
    security.sudo.wheelNeedsPassword = !cfg.security.passwordlessSudo;

    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
    };
    programs.starship = {
      enable = true;
      settings = {
        add_newline = false;
        character = {
          success_symbol = "[❯](#a6da95)";
          error_symbol = "[❯](#ed8796)";
          vimcmd_symbol = "[❮](#c6a0f6)";
        };
        directory.style = "#8aadf4";
        git_branch.style = "#c6a0f6";
        git_status.style = "#f5a97f";
      };
    };

    environment.systemPackages = [
      (pkgs.callPackage ../cli { })
    ]
    ++ map (a: agentPackages.${a}) selectedAgents
    ++ (with pkgs; [
      zellij
      git
      gh
      vim
      wget
      curl
    ])
    ++ cfg.shell.extraPackages;

    environment.sessionVariables = {
      LANI_CATALOG = catalogPath;
      LANI_SERVICES = "/etc/nixos";
      LANI_WORKTREES = "/etc/nixos/.lani-worktrees";
    };

    programs.lani.menu = {
      enable = true;
      user = cfg.user;
      agents = cfg.shell.agents;
      systemPrompt = cfg.shell.systemPrompt;
      replaceSystemPrompt = cfg.shell.replaceSystemPrompt;
    };

    programs.lani.webTerminal = {
      enable = cfg.shell.webTerminal.enable;
      user = cfg.user;
      port = cfg.shell.webTerminal.port;
      listenAddress = cfg.shell.webTerminal.listenAddress;
      openFirewall = cfg.shell.webTerminal.openFirewall;
      servicesRepo = "/etc/nixos";
      catalogPath = catalogPath;
      ciDir = "/var/lib/lani-ci";
    };

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    time.timeZone = cfg.timeZone;
  };
}
