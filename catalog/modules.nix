# Service name -> NixOS module path. Imported directly by both catalog/flake.nix and the
# root flake, so there is exactly one list.
#
# Adding a service touches three files — this, catalog.nix, and the module. `nix flake
# check` fails if they disagree.
{
  forgejo = ./modules/forgejo/module.nix;
  jellyfin = ./modules/jellyfin/module.nix;
  navidrome = ./modules/navidrome/module.nix;
  nextcloud = ./modules/nextcloud/module.nix;
  pairdrop = ./modules/pairdrop/module.nix;
  uptime-kuma = ./modules/uptime-kuma/module.nix;
  vaultwarden = ./modules/vaultwarden/module.nix;
  example = ./modules/example/module.nix;
}
