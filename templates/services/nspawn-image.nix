# Container/tarball mechanics for booting this NixOS system under systemd-nspawn
# on a non-NixOS host (tfc/nixcademy make-system-tarball recipe).
# Copied verbatim from the lani-shell repo — it is arch- and machine-name-agnostic.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [ "${modulesPath}/profiles/minimal.nix" ];

  # Run as a container: no kernel, no bootloader, no fsck, etc.
  boot.isContainer = true;
  boot.loader.grub.enable = false;

  # On first boot, register the shipped store paths into the Nix DB so that the
  # system is consistent under /nix/store.
  boot.postBootCommands = ''
    if [ -f /nix-path-registration ]; then
      ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration &&
        rm -f /nix-path-registration
    fi
    # Make this generation the active system profile.
    ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system \
      --set /run/current-system || true
  '';

  # Build the portable rootfs tarball.
  system.build.tarball = pkgs.callPackage "${toString modulesPath}/../lib/make-system-tarball.nix" {
    extraArgs = "--owner=0";

    storeContents = [
      {
        object = config.system.build.toplevel;
        symlink = "/nix/var/nix/profiles/system";
      }
    ];

    contents = [
      {
        source = config.system.build.toplevel + "/etc/os-release";
        target = "/etc/os-release";
      }
    ];

    # systemd-nspawn --boot looks for /sbin/init. Point it at the NixOS init.
    extraCommands = pkgs.writeScript "extra-commands.sh" ''
      mkdir -p proc sys dev sbin etc
      ln -s /nix/var/nix/profiles/system/init sbin/init
    '';
  };
}
