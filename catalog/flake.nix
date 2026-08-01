{
  description = "Lani service catalog — NixOS modules for self-hosted services";

  # No inputs: these are plain NixOS modules, evaluated against whatever nixpkgs the
  # importing system already uses.

  outputs =
    { self, ... }:
    {
      # One module per service. The platform itself is `lani.nixosModules.platform`.
      nixosModules = builtins.mapAttrs (_name: path: import path) (import ./modules.nix);

      # Metadata for `lani modules list`, via `nix eval --json <flake>#catalog`.
      catalog = import ./catalog.nix;

      # Persistent directories and generated credentials each service needs.
      hostRequirements = import ./host.nix;
    };
}
