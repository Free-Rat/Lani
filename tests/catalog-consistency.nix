# The catalog is described in three places — modules.nix, catalog.nix, and the module's
# own `lani.services.<name>` — and nothing stops them drifting. They had.
#
# Evaluation only: no VM, runs anywhere.
{
  pkgs,
  lib,
  self,
}:
let
  catalogEntries = import ../catalog/catalog.nix;
  catalogModules = import ../catalog/modules.nix;

  # Evaluate a real system with every catalog service and read back what got published.
  evaluated = lib.nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;
    modules = [
      self.nixosModules.platform
      { nixpkgs.pkgs = pkgs; }
      {
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        system.stateVersion = "25.05";
      }
    ]
    ++ lib.attrValues (lib.mapAttrs (_: path: import path) catalogModules);
  };

  published = evaluated.config.lani.services;

  entryNames = lib.sort (a: b: a < b) (map (e: e.name) catalogEntries);
  moduleNames = lib.sort (a: b: a < b) (lib.attrNames catalogModules);

  problems =
    lib.optional (entryNames != moduleNames) ''
      catalog.nix and modules.nix list different services.
        catalog.nix: ${lib.concatStringsSep ", " entryNames}
        modules.nix: ${lib.concatStringsSep ", " moduleNames}
    ''

    # Every catalogued service registers itself under its own name.
    ++ lib.concatMap (
      name:
      lib.optional (!(published ? ${name})) ''
        ${name} is in the catalog but never declares lani.services.${name}.
        Declared instead: ${lib.concatStringsSep ", " (lib.attrNames published)}
      ''
    ) entryNames

    # The advertised subdomain and port match what the module publishes.
    ++ lib.concatMap (
      entry:
      let
        svc = published.${entry.name} or null;
      in
      lib.optionals (svc != null) (
        lib.optional (svc.subdomain != entry.subdomain) ''
          ${entry.name}: catalog.nix says subdomain "${entry.subdomain}", the module publishes "${svc.subdomain}".
        ''
        ++ lib.optional (svc.port != entry.port) ''
          ${entry.name}: catalog.nix says port ${toString entry.port}, the module publishes ${toString svc.port}.
        ''
      )
    ) catalogEntries;
in
pkgs.runCommand "lani-catalog-consistency"
  {
    # Forcing the manifest means the whole platform config had to evaluate.
    manifest = evaluated.config.environment.etc."lani-health-manifest.json".text;
  }
  (
    if problems == [ ] then
      ''
        echo "catalog is consistent: ${toString (builtins.length entryNames)} services"
        printf '%s\n' "$manifest" > "$out"
      ''
    else
      ''
        echo "catalog inconsistencies:" >&2
        ${lib.concatMapStringsSep "\n" (p: "echo ${lib.escapeShellArg p} >&2") problems}
        exit 1
      ''
  )
