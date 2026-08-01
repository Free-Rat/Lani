# The `lani-shell` workbench as a NixOS container.
#
# privateNetwork = false, so its ports appear on the host's own addresses — which is why
# sshd here must not use one the host already has. The system inside is nix/shell-system.nix,
# shared with the portable nspawn image.
{
  config,
  lib,
  ...
}:
let
  cfg = config.lani;
in
lib.mkIf (cfg.enable && cfg.shell.enable) {

  # nspawn refuses to start a container whose bind-mount source is missing, so create them
  # here too — the services and CI modules may be disabled. Modes match theirs.
  systemd.tmpfiles.rules = [
    "d /var/lib/lani-ci 0775 root users - -"
    "d /var/lib/lani 0711 root root - -"
    "d ${cfg.repoPath} 0755 root root - -"
  ];

  containers.lani-shell = {
    autoStart = true;
    privateNetwork = false;

    bindMounts = {
      "/var/lib/lani-ci" = {
        hostPath = "/var/lib/lani-ci";
        isReadOnly = false;
      };
      "/var/lib/lani" = {
        hostPath = "/var/lib/lani";
        isReadOnly = false;
      };
      "/etc/nixos" = {
        hostPath = cfg.repoPath;
        isReadOnly = false;
      };
    }
    // lib.optionalAttrs cfg.lukshome.enable {
      "/home/${cfg.user}" = {
        hostPath = cfg.lukshome.mountPoint;
        isReadOnly = false;
      };
    };

    config =
      { lib, ... }:
      {
        imports = [ ../shell-system.nix ];

        # Only the options the workbench itself reads.
        lani = {
          inherit (cfg)
            user
            authorizedKeys
            timeZone
            countryCode
            ;
          security.passwordlessSudo = cfg.security.passwordlessSudo;
          shell = {
            inherit (cfg.shell)
              enable
              sshPort
              agents
              enableClaudeCode
              systemPrompt
              replaceSystemPrompt
              extraPackages
              webTerminal
              ;
          };
          lukshome.enable = cfg.lukshome.enable;
        };

        # Shared netns: the host owns networking entirely.
        systemd.network.enable = false;
        networking.useDHCP = false;
        networking.resolvconf.enable = lib.mkForce false;

        system.stateVersion = "25.05";
      };
  };

  systemd.services."container@lani-shell" = lib.mkIf cfg.lukshome.enable {
    after = [ "lani-luks-open.service" ];
    requires = [ "lani-luks-open.service" ];
  };
}
