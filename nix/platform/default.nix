# The Lani service platform. A service declares `lani.services.<name>` and gets an nginx
# reverse-proxy vhost, an mDNS name, firewall rules and a health-manifest entry.
#
# Backends must bind 127.0.0.1: the proxy is the only public door. See docs/catalog.md.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lani;
  services = cfg.services;
  hasServices = services != { };

  certDir = "/var/lib/lani-certs";

  serviceSubmodule =
    { name, ... }:
    {
      options = {
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = ''Hostname without the .local suffix ("nextcloud" -> nextcloud.local).'';
        };
        port = lib.mkOption {
          type = lib.types.port;
          description = "Loopback TCP port the app listens on. The proxy targets this.";
        };
        description = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Human-readable label used in the mDNS advertisement.";
        };
        tls = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Also serve https on :443 with a certificate generated on first boot. Plain
            http on :80 stays available either way.

            Self-signed means a browser warning the first time. Some things need it
            anyway: browsers restrict the Web Crypto API to secure contexts, so password
            managers do not work over plain http.
          '';
        };
        default = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Make this the nginx `default_server`, so a request to the container's raw
            address with no matching Host lands here. At most one service may set it.
          '';
        };
        proxyWebsockets = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Forward WebSocket upgrade headers. Anything with live updates — chat,
            dashboards, peer discovery, playback sync — needs this, and the failure mode
            without it is a page that loads fine and then never updates.
          '';
        };
        maxBodySize = lib.mkOption {
          type = lib.types.str;
          default = "512m";
          description = ''
            `client_max_body_size` on the proxy vhost. nginx defaults to 1M, which is
            small enough that file uploads fail before the app ever sees them.
          '';
        };
        publicDomain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Public FQDN to additionally serve over Let's Encrypt TLS. Requires
            {option}`lani.acmeEmail`, public DNS pointing here, and 80/443 reachable
            from the internet.
          '';
        };
        extraVhostConfig = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Escape hatch, merged into the generated nginx vhost attrset.";
        };
      };
    };

  anyTls = lib.any (svc: svc.tls) (lib.attrValues services);
  anyPublic = lib.any (svc: svc.publicDomain != null) (lib.attrValues services);
  tlsServices = lib.filterAttrs (_: svc: svc.tls) services;
  localDomains = lib.mapAttrsToList (_: svc: "${svc.subdomain}.local") services;

  proxyVhost =
    _name: svc:
    lib.nameValuePair "${svc.subdomain}.local" (
      lib.recursiveUpdate (
        {
          default = svc.default;
          # Required: NixOS only emits ssl_certificate when one of
          # addSSL/forceSSL/onlySSL/enableACME is set. A hand-written `listen ... ssl` is
          # not enough, and nginx then rejects the whole config.
          addSSL = svc.tls;
          listen = [
            {
              addr = "0.0.0.0";
              port = 80;
              ssl = false;
            }
          ]
          ++ lib.optional svc.tls {
            addr = "0.0.0.0";
            port = 443;
            ssl = true;
          };
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString svc.port}";
            proxyWebsockets = svc.proxyWebsockets;
          };
          extraConfig = "client_max_body_size ${svc.maxBodySize};";
        }
        // lib.optionalAttrs svc.tls {
          sslCertificate = "${certDir}/${svc.subdomain}.local/cert.pem";
          sslCertificateKey = "${certDir}/${svc.subdomain}.local/key.pem";
        }
      ) svc.extraVhostConfig
    );

  publicVhost =
    _name: svc:
    lib.nameValuePair svc.publicDomain {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString svc.port}";
        proxyWebsockets = svc.proxyWebsockets;
      };
      extraConfig = "client_max_body_size ${svc.maxBodySize};";
    };

  publicVhosts = lib.listToAttrs (
    lib.mapAttrsToList publicVhost (lib.filterAttrs (_: svc: svc.publicDomain != null) services)
  );

  avahiXml =
    svc:
    let
      proto = if svc.tls then "_https._tcp" else "_http._tcp";
      port = if svc.tls then 443 else 80;
    in
    ''
      <?xml version="1.0" standalone='no'?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">${svc.description} on %h</name>
        <service>
          <type>${proto}</type>
          <port>${toString port}</port>
        </service>
      </service-group>
    '';
in
{
  options.lani = {
    services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule serviceSubmodule);
      default = { };
      description = ''
        Services to publish on the LAN, keyed by service name. Each entry generates a
        reverse-proxy vhost at `<subdomain>.local` and an mDNS advertisement.

        Not to be confused with {option}`lani.serviceHost.activeModules`, which is the
        host-side list of which catalog modules to run at all.
      '';
    };

    acmeEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Let's Encrypt contact address. Required if any service sets `publicDomain`.";
    };

    uplinkInterface = lib.mkOption {
      type = lib.types.str;
      default = "host0";
      description = ''
        Interface whose address the mDNS records point at. `host0` is the name
        systemd-nspawn gives the container end of the veth pair, which is the normal case.
        Change it if you run the platform directly on a host rather than in a container.
      '';
    };

    countryCode = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "GB";
      description = ''
        ISO 3166-1 alpha-2 code, for the handful of services that need a default region —
        Nextcloud uses it to parse phone numbers written without a country prefix. Left
        unset, those services simply do not get a default.
      '';
    };
  };

  config = lib.mkIf hasServices {

    assertions = [
      {
        assertion = lib.count (svc: svc.default) (lib.attrValues services) <= 1;
        message = "lani: at most one service may set `default = true`.";
      }
      {
        assertion = !anyPublic || cfg.acmeEmail != null;
        message = "lani: set lani.acmeEmail when any service declares a publicDomain.";
      }
    ];

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      virtualHosts = (lib.listToAttrs (lib.mapAttrsToList proxyVhost services)) // publicVhosts;
    };

    # nginx cannot start before the certificates it references exist.
    systemd.services.nginx.after = lib.optional anyTls "lani-selfsigned-certs.service";

    security.acme = lib.mkIf anyPublic {
      acceptTerms = true;
      defaults.email = cfg.acmeEmail;
    };

    systemd.services.lani-selfsigned-certs = lib.mkIf anyTls {
      description = "Generate self-signed certificates for .local services";
      wantedBy = [ "multi-user.target" ];
      before = [ "nginx.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.openssl
        pkgs.coreutils
      ];
      script = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          _: svc:
          let
            d = "${svc.subdomain}.local";
          in
          ''
            dir=${lib.escapeShellArg "${certDir}/${d}"}
            if [ ! -s "$dir/cert.pem" ]; then
              mkdir -p "$dir"
              openssl req -x509 -newkey rsa:2048 -nodes \
                -keyout "$dir/key.pem" -out "$dir/cert.pem" -days 3650 \
                -subj "/CN=${d}" -addext "subjectAltName=DNS:${d}"
              chmod 0644 "$dir/cert.pem" "$dir/key.pem"
            fi
          ''
        ) tlsServices
      );
    };

    networking.firewall.allowedTCPPorts = [ 80 ] ++ lib.optional (anyTls || anyPublic) 443;

    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true; # UDP 5353, without which none of this resolves
      publish = {
        enable = true;
        addresses = true;
        workstation = false;
        userServices = true;
      };
    };

    # avahi owns .local here; keep systemd-resolved's mDNS responder off port 5353.
    services.resolved.settings.Resolve.MulticastDNS = "no";

    environment.etc =
      # Declarative, so removing a service removes its advertisement.
      lib.mapAttrs' (
        name: svc: lib.nameValuePair "avahi/services/${name}.service" { text = avahiXml svc; }
      ) services
      // {
        # What ci/health.sh reads, so it can check services it was never taught about.
        "lani-health-manifest.json".text = builtins.toJSON {
          services = lib.mapAttrs (_: svc: { inherit (svc) subdomain port tls; }) services;
        };
      };

    # avahi only publishes its own hostname, so each <subdomain>.local needs an explicit
    # record. The publishers must keep running to keep the records alive; exiting when one
    # dies lets systemd restart us and pick up a changed address.
    systemd.services.lani-mdns-aliases = {
      description = "Publish <subdomain>.local mDNS records for the live LAN address";
      after = [
        "avahi-daemon.service"
        "systemd-networkd.service"
      ];
      wants = [ "avahi-daemon.service" ];
      bindsTo = [ "avahi-daemon.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.avahi
        pkgs.iproute2
        pkgs.gawk
        pkgs.coreutils
      ];
      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
      };
      script = ''
        iface=${lib.escapeShellArg cfg.uplinkInterface}
        ip=""
        for _ in $(seq 1 30); do
          ip="$(ip -4 -o addr show "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
          [ -n "$ip" ] && break
          sleep 2
        done
        if [ -z "$ip" ]; then
          echo "$iface still has no IPv4 address" >&2
          exit 1
        fi
        for name in ${lib.concatStringsSep " " localDomains}; do
          echo "publishing $name -> $ip"
          avahi-publish -a -R "$name" "$ip" &
        done
        wait -n
      '';
    };
  };
}
