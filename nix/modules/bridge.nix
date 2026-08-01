# Optionally create the bridge the services container attaches to. Off by default: it
# reconfigures your uplink, so do it from a local console the first time.
{ config, lib, ... }:
let
  cfg = config.lani;
in
lib.mkIf (cfg.enable && cfg.serviceHost.enable && cfg.serviceHost.createBridge) {

  assertions = [
    {
      assertion = cfg.serviceHost.uplinkInterface != null;
      message = ''
        lani.serviceHost.createBridge is set but lani.serviceHost.uplinkInterface is not.
        A bridge with no port leaves the services container with no way onto the LAN.
        Run `ip link` and set it to your wired interface.
      '';
    }
  ];

  systemd.network = {
    enable = lib.mkDefault true;

    netdevs."10-lani-bridge".netdevConfig = {
      Name = cfg.serviceHost.bridge;
      Kind = "bridge";
    };

    networks."05-lani-uplink" = {
      matchConfig.Name = cfg.serviceHost.uplinkInterface;
      networkConfig.Bridge = cfg.serviceHost.bridge;
      linkConfig.RequiredForOnline = "enslaved";
    };

    networks."10-lani-bridge" = {
      matchConfig.Name = cfg.serviceHost.bridge;
      # No address of its own; the container gets one from your router.
      networkConfig.DHCP = "no";
      linkConfig.RequiredForOnline = "no";
    };
  };
}
