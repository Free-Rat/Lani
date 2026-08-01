# Option interface for Lani. Two groups share the `lani.` prefix and are easy to confuse:
#
#   lani.serviceHost.*   — how this host runs the services container
#   lani.services.<name> — a publish declaration read by the platform (nix/platform),
#                          set by catalog modules
#
# Separate on purpose, so a host running the platform directly can use both.
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.lani = {
    enable = mkEnableOption "Lani (agent workbench + services containers on this NixOS host)";

    user = mkOption {
      type = types.str;
      default = "lani";
      example = "alice";
      description = ''
        Login account created in both containers: who you SSH in as, who the agents run
        as, and who owns the LUKS home. Changing it does not migrate `/home`.
      '';
    };

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "ssh-ed25519 AAAA... you@laptop" ];
      description = ''
        SSH public keys for {option}`lani.user` in both containers. Password
        authentication is disabled, so with an empty list there is no way in over SSH.
      '';
    };

    timeZone = mkOption {
      type = types.str;
      default = "UTC";
      example = "Europe/London";
      description = "Timezone for both containers.";
    };

    repoPath = mkOption {
      type = types.str;
      default = "/etc/nixos";
      description = ''
        The git repository agents edit, bind-mounted into the workbench at `/etc/nixos`.
        Start one with `nix flake init -t github:Free-Rat/Lani#services`.
      '';
    };

    catalog = mkOption {
      type = types.attrsOf types.raw;
      default = import ../../catalog/modules.nix;
      defaultText = lib.literalMD "the catalog bundled with Lani";
      example = lib.literalExpression "inputs.my-catalog.nixosModules";
      description = ''
        Service modules keyed by name, which {option}`lani.serviceHost.activeModules`
        selects from. Defaults to the bundled catalog; point it at your own fork —
        `github:Free-Rat/Lani?dir=catalog` is a flake in its own right.
      '';
    };

    countryCode = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "GB";
      description = ''
        ISO 3166-1 alpha-2 code, for services that need a default region — Nextcloud uses
        it to parse phone numbers without a country prefix.
      '';
    };

    security.passwordlessSudo = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Let {option}`lani.user` run `sudo` without a password. Convenient for unattended
        agent work; combined with an exposed web terminal it hands root to anyone who can
        reach the port.
      '';
    };

    # ── Workbench container ───────────────────────────────────────────────────
    shell = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the `lani-shell` workbench container.";
      };

      sshPort = mkOption {
        type = types.port;
        default = 2222;
        description = ''
          SSH port for the workbench. It shares the host's network namespace, so this
          must not clash with the host's own sshd.
        '';
      };

      agents = mkOption {
        type = types.listOf (
          types.enum [
            "pi"
            "opencode"
            "claude"
            "shell"
          ]
        );
        default = [
          "pi"
          "opencode"
          "shell"
        ];
        description = ''
          Coding agents offered in the session menu, in order. `claude` requires
          {option}`lani.shell.enableClaudeCode` because `claude-code` is unfree; the
          default set is free software only.
        '';
      };

      enableClaudeCode = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Install Anthropic's `claude-code`. **Unfree** — this also adds an
          `allowUnfreePredicate` for it, which is a licensing decision only you can make.
        '';
      };

      systemPrompt = mkOption {
        type = types.lines;
        default = ''
          You are a homelab automation agent running on a Lani host.
          Your work lives under ~/projects.
          Use `lani modules list` to see available services.
          Use `lani modules use <name>` to install and test a service.
        '';
        description = "System prompt injected into agent sessions.";
      };

      replaceSystemPrompt = mkOption {
        type = types.bool;
        default = false;
        description = "Replace the agent's built-in prompt instead of appending to it.";
      };

      extraPackages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Extra packages to install in the workbench container.";
      };

      webTerminal = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Serve the browser-based terminal and session manager.";
        };

        port = mkOption {
          type = types.port;
          default = 7681;
          description = "Port the web terminal listens on.";
        };

        listenAddress = mkOption {
          type = types.str;
          default = "127.0.0.1";
          example = "0.0.0.0";
          description = ''
            **The web terminal has no authentication.** Anyone who can open the page gets
            an interactive shell as {option}`lani.user`. Loopback by default; reach it
            with `ssh -L 7681:127.0.0.1:7681 <host>`.

            `0.0.0.0` publishes that shell to your whole LAN. Only behind a VPN or an
            authenticating proxy.
          '';
        };

        openFirewall = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Open {option}`lani.shell.webTerminal.port` in the firewall. Read the warning
            on {option}`lani.shell.webTerminal.listenAddress` first.
          '';
        };
      };
    };

    # ── Services container ────────────────────────────────────────────────────
    serviceHost = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the `lani-services` container.";
      };

      activeModules = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "nextcloud"
          "vaultwarden"
          "jellyfin"
        ];
        description = ''
          Catalog services to run; each name must be a key of {option}`lani.catalog`.
          Try one first with `lani modules use <name>`, which builds and boots it in a
          throwaway container.
        '';
      };

      networking = mkOption {
        type = types.enum [
          "bridge"
          "nat"
        ];
        default = "bridge";
        description = ''
          `bridge` puts the container on your LAN with its own DHCP address. This is what
          you want on a real host: mDNS is link-local, so `<name>.local` only resolves for
          other machines when the container is on the same link.

          `nat` gives it a point-to-point link to the host instead. Nothing on the LAN
          sees it and mDNS does not propagate, but it needs nothing from your network —
          which is why the demo VM uses it.
        '';
      };

      bridge = mkOption {
        type = types.str;
        default = "br0";
        description = ''
          Host bridge the container's veth pair joins, when
          {option}`lani.serviceHost.networking` is `bridge`.
        '';
      };

      hostAddress = mkOption {
        type = types.str;
        default = "192.168.101.1";
        description = "Host end of the point-to-point link, in `nat` mode.";
      };

      containerAddress = mkOption {
        type = types.str;
        default = "192.168.101.2";
        description = "Container end of the point-to-point link, in `nat` mode.";
      };

      externalInterface = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "eth0";
        description = ''
          The host's own uplink, in `nat` mode. Without it only the host can reach the
          services; with it, 80/443 arriving there are forwarded to the container.
        '';
      };

      createBridge = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Create {option}`lani.serviceHost.bridge` and enslave
          {option}`lani.serviceHost.uplinkInterface` to it. This reconfigures your uplink:
          the NIC gives up its address and becomes a bridge port. Do it from a local
          console the first time, not over SSH.
        '';
      };

      uplinkInterface = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "eth0";
        description = ''
          NIC to attach to the bridge when {option}`lani.serviceHost.createBridge` is
          set. Check `ip link`.
        '';
      };

      acmeEmail = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Let's Encrypt contact address, for services that set `publicDomain`. `.local`
          names use a self-signed certificate.
        '';
      };

      extraBindMounts = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              hostPath = mkOption {
                type = types.str;
                description = "Path on the host to bind into the container.";
              };
              isReadOnly = mkOption {
                type = types.bool;
                default = false;
                description = "Mount read-only.";
              };
            };
          }
        );
        default = { };
        example = lib.literalExpression ''{ "/var/lib/jellyfin/media".hostPath = "/srv/media"; }'';
        description = ''
          Extra bind mounts, keyed by the path inside the container, for services that
          need bulk storage.
        '';
      };
    };

    # ── Encrypted home ────────────────────────────────────────────────────────
    lukshome = {
      enable = mkEnableOption "LUKS-encrypted home volume for the workbench user";

      imagePath = mkOption {
        type = types.str;
        default = "/var/lib/lani-shell/home.img";
        description = "Host path to the LUKS image. Created on first boot if absent.";
      };

      imageSizeGB = mkOption {
        type = types.int;
        default = 8;
        description = "Size to allocate when creating the image. First boot only.";
      };

      keyPath = mkOption {
        type = types.str;
        default = "/var/lib/lani-shell/home.key";
        description = ''
          LUKS key file, root-owned 0400, generated on first boot. **Back it up.** Lose
          it and the volume is unrecoverable — no passphrase, no recovery key.
        '';
      };

      mountPoint = mkOption {
        type = types.str;
        default = "/run/lani-shell/home";
        description = "Where the decrypted volume is mounted before the container starts.";
      };
    };
  };
}
