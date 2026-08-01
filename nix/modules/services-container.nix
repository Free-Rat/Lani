# The `lani-services` container: the platform plus the catalog services you enabled.
#
# It has its own network namespace. In `bridge` mode it also gets its own LAN address,
# which is what makes `<name>.local` resolve from other machines — mDNS is link-local.
# `nat` mode puts it behind the host instead and needs nothing from your network.
#
# The container is re-imported wholesale on deploy, so persistent state lives on the host;
# what each service needs is declared in catalog/host.nix.
{
  config,
  lib,
  ...
}:
let
  cfg = config.lani;
  bridged = cfg.serviceHost.networking == "bridge";

  needs = import ../host-requirements.nix {
    inherit lib;
    activeModules = cfg.serviceHost.activeModules;
  };

  stateRoot = "/var/lib/lani";

  # nspawn names the container end host0; with a point-to-point link NixOS renames it eth0.
  containerIface = if bridged then "host0" else "eth0";

  networkAttrs =
    if bridged then
      { hostBridge = cfg.serviceHost.bridge; }
    else
      {
        hostAddress = cfg.serviceHost.hostAddress;
        localAddress = cfg.serviceHost.containerAddress;
      };
in
lib.mkIf (cfg.enable && cfg.serviceHost.enable) {

  assertions = [
    {
      assertion = lib.all (name: cfg.catalog ? ${name}) cfg.serviceHost.activeModules;
      message =
        let
          missing = lib.filter (name: !(cfg.catalog ? ${name})) cfg.serviceHost.activeModules;
        in
        ''
          lani.serviceHost.activeModules names services that are not in lani.catalog:
            ${lib.concatStringsSep ", " missing}
          Available: ${lib.concatStringsSep ", " (lib.attrNames cfg.catalog)}
        '';
    }
  ];

  systemd.tmpfiles.rules = [
    "d ${stateRoot} 0711 root root - -"
  ]
  ++ map (s: "d ${stateRoot}/${s.dir} ${s.mode} root root - -") needs.state;

  # Generated on the host: never in the Nix store, and survives a container re-import.
  systemd.services = lib.listToAttrs (
    map (
      s:
      lib.nameValuePair "lani-secret-${s.fileName}" {
        description = "Generate ${s.fileName} if absent";
        before = [ "container@lani-services.service" ];
        wantedBy = [ "container@lani-services.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          target=${lib.escapeShellArg "${stateRoot}/${s.fileName}"}
          if [ ! -s "$target" ]; then
            install -m 0600 /dev/null "$target"
            head -c 18 /dev/urandom | base64 > "$target"
            echo "lani: generated $target"
          fi
        '';
      }
    ) needs.secrets
  );

  # In nat mode the host stands in for the container: it forwards 80/443 inward and
  # resolves the `.local` names itself, since mDNS does not cross the link.
  networking = lib.mkIf (!bridged) {
    nat = {
      enable = true;
      # By address, not interface name: "ve-lani-services" is 16 characters against a
      # 15-character limit, so nspawn renames it to an unpredictable hash — and iptables
      # rejects the oversized name with status 2, failing the whole firewall unit.
      internalIPs = [ "${cfg.serviceHost.containerAddress}/32" ];
      externalInterface = cfg.serviceHost.externalInterface;
      # Needs an uplink to forward from; without one only the host can reach the services.
      forwardPorts = lib.optionals (cfg.serviceHost.externalInterface != null) [
        {
          sourcePort = 80;
          destination = "${cfg.serviceHost.containerAddress}:80";
          proto = "tcp";
        }
        {
          sourcePort = 443;
          destination = "${cfg.serviceHost.containerAddress}:443";
          proto = "tcp";
        }
      ];
    };

    hosts.${cfg.serviceHost.containerAddress} = lib.mapAttrsToList (
      _: svc: "${svc.subdomain}.local"
    ) config.containers.lani-services.config.lani.services;
  };

  containers.lani-services = networkAttrs // {
    autoStart = true;
    privateNetwork = true;

    bindMounts =
      lib.listToAttrs (
        map (
          s:
          lib.nameValuePair s.containerPath {
            hostPath = "${stateRoot}/${s.fileName}";
            isReadOnly = true;
          }
        ) needs.secrets
      )
      // lib.listToAttrs (
        map (
          s:
          lib.nameValuePair s.containerPath {
            hostPath = "${stateRoot}/${s.dir}";
            isReadOnly = false;
          }
        ) needs.state
      )
      // cfg.serviceHost.extraBindMounts;

    config =
      { pkgs, ... }:
      {
        imports = [
          ../platform
        ]
        ++ map (name: cfg.catalog.${name}) cfg.serviceHost.activeModules;

        networking.hostName = "lani-services";

        lani.acmeEmail = cfg.serviceHost.acmeEmail;
        lani.countryCode = cfg.countryCode;
        lani.uplinkInterface = containerIface;

        # Only in bridge mode: in nat mode the container module already set a static
        # address, and DHCP would fight it.
        systemd.network = lib.mkIf bridged {
          enable = true;
          networks."10-uplink" = {
            matchConfig.Name = containerIface;
            networkConfig.DHCP = "yes";
            linkConfig.RequiredForOnline = "routable";
          };
        };
        networking.useDHCP = false;
        networking.useHostResolvConf = !bridged;
        services.resolved.enable = lib.mkDefault bridged;

        networking.firewall.enable = true;
        # The platform adds 80/443 and avahi 5353. Backends stay on loopback.
        networking.firewall.allowedTCPPorts = [ 22 ];

        services.openssh = {
          enable = true;
          settings = {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            PermitRootLogin = "no";
          };
        };

        users.users.${cfg.user} = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          openssh.authorizedKeys.keys = cfg.authorizedKeys;
          shell = pkgs.zsh;
        };
        programs.zsh.enable = true;
        security.sudo.wheelNeedsPassword = !cfg.security.passwordlessSudo;

        environment.systemPackages = with pkgs; [
          git
          vim
          curl
          wget
        ];
        nix.settings.experimental-features = [
          "nix-command"
          "flakes"
        ];
        time.timeZone = cfg.timeZone;
        system.stateVersion = "25.05";
      };
  };
}
