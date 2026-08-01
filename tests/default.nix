# Flake checks. The VM tests want KVM.
{
  pkgs,
  lib,
  self,
}:
{
  catalog-consistency = import ./catalog-consistency.nix { inherit pkgs lib self; };
  health-check = import ./health-check.nix { inherit pkgs lib self; };
  shell-boots = import ./shell-boots.nix { inherit pkgs lib self; };
  services-health = import ./services-health.nix { inherit pkgs lib self; };
}
