# Does the CI gate actually fail when a service is broken? It did not: the checks ran in
# a subshell on the right of a pipe with no `set -e`, so `exit 1` was swallowed and the
# script always returned 0.
#
# Stubs machinectl and systemd-run rather than booting anything — what is under test is
# control flow — so it runs anywhere in seconds.
{
  pkgs,
  lib,
  self,
}:
let
  manifest = builtins.toJSON {
    services.demo = {
      subdomain = "demo";
      port = 9999;
      tls = false;
    };
  };

  # The command to run in the "machine" is the last argument. PORT_UP and HTTP_OK decide
  # whether the checks pass.
  fakeSystemdRun = pkgs.writeShellScript "systemd-run" ''
    cmd="''${*: -1}"
    case "$cmd" in
      *lani-health-manifest*) cat "$LANI_TEST_MANIFEST" ;;
      *"ss -tln"*)            [ "''${PORT_UP:-0}" = 1 ] ;;
      *curl*)                 [ "''${HTTP_OK:-0}" = 1 ] ;;
      *"ip -4"*)              echo "10.9.9.9" ;;
      *)                      exit 1 ;;
    esac
  '';

  fakeMachinectl = pkgs.writeShellScript "machinectl" ''
    exit 0
  '';

  health = pkgs.writeShellApplication {
    name = "lani-health";
    runtimeInputs = [ pkgs.python3 ];
    text = builtins.readFile ../ci/health.sh;
  };
in
pkgs.runCommand "lani-health-check-behaviour"
  {
    nativeBuildInputs = [
      health
      pkgs.python3
    ];
    inherit manifest;
  }
  ''
    set -euo pipefail

    mkdir -p stub
    ln -s ${fakeSystemdRun} stub/systemd-run
    ln -s ${fakeMachinectl} stub/machinectl
    export PATH="$PWD/stub:$PATH"

    printf '%s' "$manifest" > manifest.json
    export LANI_TEST_MANIFEST="$PWD/manifest.json"

    # Short timeout: the failing cases poll until the deadline.
    run() { lani-health demo-machine 5 eth0; }

    echo "--- a service that never listens must fail"
    PORT_UP=0 HTTP_OK=0 run && { echo "FAIL: exited 0 with a dead service" >&2; exit 1; }
    echo "ok"

    echo "--- a service that listens but does not answer must fail"
    PORT_UP=1 HTTP_OK=0 run && { echo "FAIL: exited 0 with a broken vhost" >&2; exit 1; }
    echo "ok"

    echo "--- a healthy service must pass, and print the address on stdout"
    ip="$(PORT_UP=1 HTTP_OK=1 run 2>/dev/null)"
    [ "$ip" = "10.9.9.9" ] || { echo "FAIL: expected the address, got '$ip'" >&2; exit 1; }
    echo "ok"

    echo "--- a container with no manifest must fail, not pass vacuously"
    : > empty.json
    LANI_TEST_MANIFEST="$PWD/empty.json" run \
      && { echo "FAIL: exited 0 with no manifest" >&2; exit 1; }
    echo "ok"

    touch "$out"
  ''
