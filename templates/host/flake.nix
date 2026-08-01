{
  description = "A NixOS host running Lani";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lani = {
      url = "github:Free-Rat/Lani";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, lani, ... }:
    {
      nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux"; # aarch64-linux for a Raspberry Pi
        modules = [
          lani.nixosModules.default
          ./configuration.nix
          # From nixos-generate-config on the machine itself.
          ./hardware-configuration.nix
        ];
      };
    };
}
