# Lani — NixOS module. Import this on the host that should run the platform.
#
# In your flake.nix:
#   inputs.lani.url = "github:Free-Rat/Lani";
#
# In your configuration.nix:
#   imports = [ inputs.lani.nixosModules.default ];
#   lani = {
#     enable = true;
#     authorizedKeys = [ "ssh-ed25519 AAAA... you@laptop" ];
#     serviceHost.activeModules = [ "nextcloud" "vaultwarden" ];
#   };
#
# `lani.catalog` defaults to the bundled catalog, so nothing else is required. For a
# complete host: nix flake init -t github:Free-Rat/Lani#host
{ ... }:
{
  imports = [
    ./options.nix
    ./bridge.nix
    ./luks-home.nix
    ./ci.nix
    ./shell-container.nix
    ./services-container.nix
  ];
}
