# A Lani host.
#
#   nix run github:Free-Rat/Lani#vm        try it first, changes nothing
#   sudo nixos-rebuild switch --flake .#myhost
{ ... }:
{
  lani = {
    enable = true;

    user = "lani";

    # Required: password authentication is off, so without a key there is no way in.
    authorizedKeys = [
      # "ssh-ed25519 AAAA... you@laptop"
    ];

    timeZone = "UTC";

    # The git repository agents edit:  nix flake init -t github:Free-Rat/Lani#services
    repoPath = "/etc/nixos/lani-services";

    serviceHost = {
      # `lani modules list` shows what is available.
      activeModules = [
        "nextcloud"
        # "vaultwarden"
        # "jellyfin"
        # "forgejo"
        # "navidrome"
        # "uptime-kuma"
        # "pairdrop"
      ];

      # "bridge" gives the container its own LAN address, which is what makes
      # nextcloud.local resolve from other devices. "nat" needs nothing from your network
      # but keeps services reachable only through this host — start there if unsure.
      networking = "bridge";
      bridge = "br0";

      # Only for services that need bulk storage.
      # extraBindMounts."/media".hostPath = "/srv/media";
    };

    # claude-code is unfree; the default agents are not.
    # shell = {
    #   agents = [ "pi" "opencode" "claude" "shell" ];
    #   enableClaudeCode = true;
    # };

    # The web terminal is an unauthenticated shell, on loopback by default:
    #   ssh -L 7681:127.0.0.1:7681 <this host>
    # Exposing it publishes a shell to your whole LAN.

    # Key generated on first boot at /var/lib/lani-shell/home.key. Back it up.
    lukshome = {
      enable = false;
      imageSizeGB = 16;
    };
  };

  # ── Host networking for bridge mode ──────────────────────────────────────────
  #
  # Lani can create the bridge:
  #
  #   lani.serviceHost.createBridge = true;
  #   lani.serviceHost.uplinkInterface = "eth0";   # check `ip link`
  #
  # This moves the address off your NIC onto the bridge. Get it wrong over SSH and you
  # lose the machine, so do it from a local console the first time. Or manage it yourself:
  #
  #   networking.useDHCP = false;
  #   networking.bridges.br0.interfaces = [ "eth0" ];
  #   networking.interfaces.br0.useDHCP = true;

  networking.hostName = "myhost";
  services.openssh.enable = true;

  networking.firewall.allowedTCPPorts = [ 22 ];

  system.stateVersion = "25.05";
}
