{
  lib,
  writeShellApplication,
  runCommand,
  symlinkJoin,
  bash,
  coreutils,
  gnugrep,
  gnused,
  gawk,
  git,
  nix,
  jq,
  python3,
  zellij,
}:

let
  lani = writeShellApplication {
    name = "lani";

    # Colour codes are constants defined in the script, never user input. Cannot be a
    # directive in the file — writeShellApplication prepends its own header.
    excludeShellChecks = [ "SC2059" ];

    # shellcheck prints findings in the ambient locale and the script has box characters;
    # without this it dies on "commitBuffer: invalid argument" instead of reporting.
    derivationArgs.env.LANG = "C.UTF-8";

    runtimeInputs = [
      bash
      coreutils
      gnugrep
      gnused
      gawk
      git
      nix
      jq
      python3
      zellij
    ];
    text = builtins.readFile ./lani;
  };
in
symlinkJoin {
  name = "lani-cli";
  paths = [
    lani
    (runCommand "lani-zsh-completion" { } ''
      install -Dm644 ${./_lani} $out/share/zsh/site-functions/_lani
    '')
  ];
  meta = {
    description = "Command-line interface for the Lani homelab platform";
    mainProgram = "lani";
    license = lib.licenses.agpl3Plus;
    platforms = lib.platforms.linux;
  };
}
