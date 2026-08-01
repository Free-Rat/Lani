{
  description = "Lani — a declarative, privacy-first local AI homelab platform on NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Plus macOS, so `nix fmt` works for people writing NixOS config from a Mac.
      devSystems = systems ++ [ "aarch64-darwin" ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      forDevSystems = f: nixpkgs.lib.genAttrs devSystems (system: f nixpkgs.legacyPackages.${system});

      treefmtFor = forDevSystems (pkgs: treefmt-nix.lib.evalModule pkgs ./treefmt.nix);
    in
    {
      # ── NixOS modules ────────────────────────────────────────────────────────
      nixosModules = {
        default = ./nix/modules;

        # The service platform alone, for running services straight on a host.
        platform = ./nix/platform;

        # Turns a system into a portable rootfs tarball for `machinectl import-tar`.
        nspawnImage = ./nix/nspawn-image.nix;

        # The workbench as a whole system. See host-tools/README.md.
        shellImage = {
          imports = [
            ./nix/nspawn-image.nix
            ./nix/standalone-shell.nix
          ];
        };
      }
      # Each catalog service, for importing one directly.
      // builtins.mapAttrs (_: path: import path) (import ./catalog/modules.nix);

      # ── Packages ─────────────────────────────────────────────────────────────
      packages = forAllSystems (
        pkgs:
        {
          lani-cli = pkgs.callPackage ./cli { };
          default = pkgs.callPackage ./cli { };
        }
        # A Raspberry-Pi deliverable. Everything else runs on x86_64 too.
        // nixpkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "aarch64-linux") {
          tarball = self.nixosConfigurations.lani-shell-image.config.system.build.tarball;
        }
      );

      # ── The demo: `nix run github:Free-Rat/Lani#vm` ───────────────────────────
      apps = forAllSystems (_pkgs: {
        vm = {
          type = "app";
          program = "${self.nixosConfigurations.lani-vm.config.system.build.vm}/bin/run-lani-vm-vm";
          meta.description = "Boot the whole Lani stack in a throwaway QEMU VM";
        };
      });

      nixosConfigurations = {
        # x86_64 demo host, with the interesting ports forwarded to localhost.
        lani-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            self.nixosModules.default
            ./nix/vm.nix
          ];
        };

        # The portable rootfs, for a host that is not running NixOS.
        lani-shell-image = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            ./nix/nspawn-image.nix
            ./nix/standalone-shell.nix
          ];
        };
      };

      # ── Checks, formatter, dev shell ─────────────────────────────────────────
      # Both Linux architectures: Lani is deployed on aarch64 as often as x86_64. The VM
      # tests among these need KVM, so CI can only run those on x86_64 — GitHub's hosted
      # aarch64 runners have no /dev/kvm.
      checks = forAllSystems (
        pkgs:
        {
          formatting = treefmtFor.${pkgs.stdenv.hostPlatform.system}.config.build.check self;
        }
        // import ./tests {
          inherit pkgs self;
          inherit (nixpkgs) lib;
        }
      );

      formatter = forDevSystems (
        pkgs: treefmtFor.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper
      );

      devShells = forDevSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            nixfmt-rfc-style
            shellcheck
            shfmt
            jq
          ];
          shellHook = ''
            echo "Lani dev shell:"
            echo "  nix run .#vm      boot the whole stack in a throwaway VM"
            echo "  nix flake check   evaluation, formatting and the VM tests"
            echo "  nix fmt           format everything"
          '';
        };
      });

      templates = {
        host = {
          path = ./templates/host;
          description = "A NixOS host running Lani";
        };
        services = {
          path = ./templates/services;
          description = "A services repository for Lani agents to edit";
        };
      };
    };
}
