# Drives both `nix fmt` and the `formatting` flake check.
{ ... }:
{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;

  programs.shfmt.enable = true;
  settings.formatter.shfmt.options = [
    "--indent"
    "2"
  ];

  programs.shellcheck.enable = true;

  programs.prettier = {
    enable = true;
    includes = [
      "*.md"
      "*.json"
      "*.mjs"
    ];
  };

  settings.global.excludes = [
    "LICENSE"
    "flake.lock"
    "*.lock"
    ".editorconfig"
    ".gitattributes"
    # ini-ish, no formatter applies
    "*.nspawn"
    "*.conf"
    "*.service"
    "*.path"
  ];
}
