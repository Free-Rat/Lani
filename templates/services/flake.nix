{
  description = "Lani services — the container agents build and test";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lani = {
      url = "github:Free-Rat/Lani";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, lani, ... }:
    let
      system = "x86_64-linux"; # match your host

      services = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          lani.nixosModules.platform
          lani.nixosModules.nspawnImage
          ./configuration.nix
          ./modules
        ];
      };
    in
    {
      # What ./request-test.sh builds and queues.
      packages.${system} = {
        tarball = services.config.system.build.tarball;
        default = services.config.system.build.tarball;
      };

      nixosConfigurations.lani-services = services;
    };
}
