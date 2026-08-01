# Flattens catalog/host.nix into the two lists the host modules need. Used by
# services-container.nix (which creates and mounts them) and ci.nix (throwaway copies).
{
  lib,
  activeModules,
  requirements ? import ../catalog/host.nix,
}:
let
  active = lib.filter (name: requirements ? ${name}) activeModules;
  for = name: requirements.${name};
in
{
  # Random credentials, generated on the host, mounted read-only.
  secrets = lib.concatMap (
    name:
    lib.mapAttrsToList (containerPath: fileName: { inherit containerPath fileName; }) (
      (for name).secrets or { }
    )
  ) active;

  # Directories that must outlive a container re-import.
  state = lib.concatMap (
    name:
    lib.mapAttrsToList (containerPath: spec: {
      inherit containerPath;
      inherit (spec) dir mode;
    }) ((for name).state or { })
  ) active;
}
