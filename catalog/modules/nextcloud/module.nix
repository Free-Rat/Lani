# Nextcloud. One `lani.services` block does the plumbing; the rest is Nextcloud's own
# config plus the two awkward bits every reverse-proxied Nextcloud needs — binding its
# nginx to a loopback port, and telling it which Host headers to trust.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Nextcloud's own nginx vhost listens here. The platform proxy is the only public door.
  backendPort = 8080;
in
{
  lani.services.nextcloud = {
    subdomain = "nextcloud"; # http(s)://nextcloud.local
    port = backendPort;
    tls = true; # self-signed unless publicDomain is set
    default = true; # hitting the container's raw IP lands here
    proxyWebsockets = true; # notify_push
    maxBodySize = "2G"; # large uploads have to pass the proxy too
    description = "Nextcloud";
    # publicDomain = "cloud.example.com";  # real certificate; also set lani.acmeEmail
  };

  services.nextcloud = {
    enable = true;
    # Nextcloud cannot skip majors on upgrade, so bump this one at a time and let each
    # upgrade finish before the next.
    package = pkgs.nextcloud34;

    # Nextcloud's own nginx server block, not a public name: it must not be
    # "nextcloud.local", which belongs to the platform's proxy vhost.
    hostName = "nextcloud-backend";

    # TLS terminates at the platform proxy.
    https = false;

    # SQLite keeps this self-contained. For a busy instance use pgsql.
    config = {
      adminuser = "admin";
      # Generated on the host, bind-mounted read-only. See catalog/host.nix.
      adminpassFile = "/etc/nextcloud-admin-pass";
      dbtype = "sqlite";
    };

    settings = {
      # The proxy forwards the original Host, so the public name has to be trusted here.
      trusted_domains = [
        "localhost"
        "nextcloud-backend"
        "nextcloud.local"
      ];
      trusted_proxies = [ "127.0.0.1" ];
      overwritehost = "nextcloud.local";
      "overwrite.cli.url" = "http://nextcloud.local";
    }
    // lib.optionalAttrs (config.lani.countryCode != null) {
      # Nextcloud needs a region to parse phone numbers without a country code.
      default_phone_region = config.lani.countryCode;
    };
  };

  # Off :80, which the platform proxy occupies.
  services.nginx.virtualHosts."nextcloud-backend".listen = lib.mkForce [
    {
      addr = "127.0.0.1";
      port = backendPort;
    }
  ];

  # Reaching the container by raw IP forwards Host: <ip>, which Nextcloud rejects unless
  # trusted. The DHCP lease is unknown at build time, so add it at runtime.
  systemd.services.nextcloud-trust-ip = {
    description = "Add the live LAN address to Nextcloud trusted_domains";
    after = [
      "nextcloud-setup.service"
      "systemd-networkd.service"
    ];
    wants = [ "nextcloud-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [
      pkgs.iproute2
      config.services.nextcloud.occ
    ];
    script = ''
      iface=${lib.escapeShellArg config.lani.uplinkInterface}
      ip="$(ip -4 -o addr show "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
      if [ -n "$ip" ]; then
        nextcloud-occ config:system:set trusted_domains 3 --value="$ip" || true
      fi
    '';
  };
}
