# The demo: `nix run github:Free-Rat/Lani#vm`. A complete Lani host in a throwaway QEMU
# VM — nothing here touches the machine you run it on.
#
#   http://localhost:8080/      the example site (Host: nextcloud.local for Nextcloud)
#   http://localhost:7681/      the web terminal
#   ssh -p 2222 lani@localhost  once you have added a key
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.lani;

  # A real deployment's lani.repoPath is a git repo the user creates themselves with
  # `nix flake init -t github:Free-Rat/Lani#services` — Lani never touches it uninvited.
  # The demo has nothing to point at, so `lani modules use` would otherwise die at the
  # very first git command with "not a git repository". Bootstrap it here instead, from
  # the same template, verbatim — demo-only, gated so it only ever runs once.
  servicesTemplate = ../templates/services;

  bootstrapServicesRepo = pkgs.writeShellApplication {
    name = "lani-demo-bootstrap-services-repo";
    runtimeInputs = [
      pkgs.git
      pkgs.coreutils
    ];
    text = ''
      repo=${lib.escapeShellArg cfg.repoPath}
      shopt -s dotglob
      cp -r ${servicesTemplate}/* "$repo"/
      chmod -R u+w "$repo"
      git -C "$repo" init -q -b main
      git -C "$repo" config user.email "lani-demo@localhost"
      git -C "$repo" config user.name "Lani demo bootstrap"
      git -C "$repo" add -A
      git -C "$repo" commit -q -m "Initial services repo (demo bootstrap)"
      # cfg.user only exists as an account *inside* the containers, not on this outer
      # host — chown-by-name would fail here. Group-write for "users" (which lani.user
      # is a member of on both sides) is what actually needs to happen, so later
      # `git worktree add`/commit calls from inside the workbench can touch .git too.
      chown -R root:users "$repo"
      chmod -R g+w "$repo"
    '';
  };
in
{
  lani = {
    enable = true;
    user = "lani";

    # Empty on purpose: a published image with a key in it would be a backdoor. The
    # serial console works regardless.
    authorizedKeys = [ ];

    # A VM has no LAN to bridge onto, and a second DHCP lease from QEMU's user-mode
    # network is fragile.
    serviceHost = {
      networking = "nat";
      # QEMU puts the guest's uplink on eth0; forwarding from it is what lets the port
      # forwards below reach the container.
      externalInterface = "eth0";
      activeModules = [
        "nextcloud"
        "example"
      ];
    };

    shell = {
      # All interfaces so QEMU's port forward can reach it. A mistake on a real host —
      # this is an unauthenticated shell — but nothing outside QEMU can reach this guest.
      webTerminal.listenAddress = "0.0.0.0";
    };
  };

  services.getty.autologinUser = lib.mkDefault "root";

  systemd.services.lani-demo-bootstrap-services-repo = {
    description = "Bootstrap a git-initialized services repo at lani.repoPath (demo only)";
    after = [ "systemd-tmpfiles-setup.service" ];
    before = [
      "container@lani-shell.service"
      "container@lani-services.service"
    ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "!${cfg.repoPath}/.git";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe bootstrapServicesRepo;
    };
  };

  # lani-shell shares this VM's own netns (privateNetwork = false), so its ports are
  # filtered by this host's own firewall, not just QEMU's port forwards below. Without
  # this, 7681 and 2222 are reachable from nowhere despite nginx/sshd listening fine —
  # only the forwarded ports that land in a container's separate netns (80/443, via NAT)
  # get through on their own.
  networking.firewall.allowedTCPPorts = [
    7681
    2222
  ];

  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 4096;
      cores = 4;
      diskSize = 16384;
      graphics = false;
      forwardPorts = [
        {
          from = "host";
          host.port = 8080;
          guest.port = 80;
        }
        {
          from = "host";
          host.port = 8443;
          guest.port = 443;
        }
        {
          from = "host";
          host.port = 7681;
          guest.port = 7681;
        }
        {
          from = "host";
          host.port = 2222;
          guest.port = 2222;
        }
      ];
    };
  };

  # Only built as a VM, but it still has to evaluate as a real system.
  boot.loader.grub.enable = false;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  networking.hostName = "lani-vm";
  system.stateVersion = "25.05";
}
