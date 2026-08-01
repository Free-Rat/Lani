# The base system for the services container. Frozen during feature work: it is the one
# file every branch has in common. Features go in modules/, one file each.
{ ... }:
{
  networking.hostName = "lani-services";

  # nspawn names the container end host0; DHCP on it gets this container a LAN address.
  systemd.network = {
    enable = true;
    networks."10-uplink" = {
      matchConfig.Name = "host0";
      networkConfig.DHCP = "yes";
      linkConfig.RequiredForOnline = "routable";
    };
  };
  networking.useDHCP = false;
  networking.useHostResolvConf = false;
  services.resolved.enable = true;

  # The platform opens 80, 443 and mDNS. Backends stay on loopback.
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # lani.countryCode = "GB";              # for services needing a default region
  # lani.acmeEmail = "you@example.com";   # only for services that set publicDomain

  system.stateVersion = "25.05";
}
