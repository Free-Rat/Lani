# The workbench comes up and both ways in answer. Also checks the default security
# posture: the web terminal must not be reachable from another machine. That default is
# all that stands between a fresh install and an unauthenticated public shell.
{
  pkgs,
  lib,
  self,
}:
pkgs.testers.runNixOSTest {
  name = "lani-shell-boots";

  nodes = {
    host =
      { ... }:
      {
        imports = [ self.nixosModules.default ];

        lani = {
          enable = true;
          serviceHost.enable = false;
          shell = {
            enable = true;
            agents = [ "shell" ]; # no agent packages: nothing to download
          };
        };

        environment.systemPackages = [
          pkgs.curl
          pkgs.iproute2
        ];

        virtualisation = {
          memorySize = 2048;
          cores = 2;
          diskSize = 4096;
        };
      };

    # A second machine, purely to prove the web terminal is *not* reachable from it.
    peer =
      { ... }:
      {
        environment.systemPackages = [ pkgs.curl ];
      };
  };

  testScript = ''
    start_all()
    host.wait_for_unit("multi-user.target")
    peer.wait_for_unit("multi-user.target")

    with subtest("the workbench container starts"):
        host.wait_for_unit("container@lani-shell.service")
        host.wait_until_succeeds("machinectl show lani-shell", timeout=120)

    with subtest("sshd answers on the configured port"):
        # privateNetwork = false, so the container's sshd is on the host's addresses.
        host.wait_for_open_port(2222)
        banner = host.succeed(
            "timeout 10 bash -c 'exec 3<>/dev/tcp/127.0.0.1/2222; head -n1 <&3'"
        )
        assert banner.startswith("SSH-"), f"not an ssh banner: {banner!r}"

    with subtest("the web terminal serves its page"):
        host.wait_for_open_port(7681)
        host.wait_until_succeeds("curl -fsS http://127.0.0.1:7681/ | grep -q '<title>lani</title>'", timeout=120)

    with subtest("the web terminal is not exposed off-host by default"):
        # If this ever passes from `peer`, the default has regressed into a remote shell.
        host.fail("ss -tlnp | grep -E '0\\.0\\.0\\.0:7681|\\*:7681'")
        peer.fail("curl -fsS --max-time 5 http://host:7681/")

    with subtest("the lani CLI is installed and runs"):
        # systemd-run, not `machinectl shell`: the latter wants a PTY the driver has not got.
        host.succeed(
            "systemd-run --machine=lani-shell --quiet --pipe --wait --collect "
            "/run/current-system/sw/bin/lani --help 2>&1 | grep -qi modules"
        )
  '';
}
