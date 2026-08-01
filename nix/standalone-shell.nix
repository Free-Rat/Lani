# The workbench as a standalone system for the portable nspawn rootfs, started with
# `machinectl import-tar` on a host that is not running NixOS. On a NixOS host use
# nixosModules.default instead, which runs this same system as a container.
{ lib, ... }:
{
  imports = [ ./shell-system.nix ];

  lani = {
    enable = true;

    # Empty by design: a published image with a key baked in would be a backdoor. This is
    # a reference build — override it from your own flake. See host-tools/README.md.
    authorizedKeys = [ ];
  };

  # Shares the host's network namespace: do not touch interfaces or resolv.conf.
  systemd.network.enable = false;
  networking.useDHCP = false;
  networking.resolvconf.enable = lib.mkForce false;

  system.stateVersion = "25.05";
}
