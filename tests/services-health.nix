# End to end: the services container comes up behind the platform's proxy and the catalog
# services answer on their own names. Nextcloud is included deliberately — it is the
# fussiest service in the catalog, so if it comes up green the plumbing works.
{
  pkgs,
  lib,
  self,
}:
pkgs.testers.runNixOSTest {
  name = "lani-services-health";

  nodes.host =
    { ... }:
    {
      imports = [ self.nixosModules.default ];

      lani = {
        enable = true;
        shell.enable = false; # not what this test is about
        serviceHost = {
          networking = "nat";
          activeModules = [
            "example"
            "nextcloud"
          ];
        };
      };

      environment.systemPackages = [ pkgs.curl ];

      virtualisation = {
        memorySize = 4096;
        cores = 4;
        diskSize = 8192;
        writableStoreUseTmpfs = false;
      };
    };

  testScript = ''
    import json

    start_all()
    host.wait_for_unit("multi-user.target")

    with subtest("the host firewall is actually up"):
        # It was not: a 16-character interface name in an iptables rule made the unit
        # exit 2, and the host ran with no rules. Nothing else here noticed.
        host.succeed("systemctl is-active firewall.service")

    with subtest("the services container starts"):
        host.wait_for_unit("container@lani-services.service")
        host.wait_until_succeeds("machinectl show lani-services", timeout=180)

    with subtest("the platform generated a health manifest"):
        # systemd-run, not `machinectl shell`: the latter wants a PTY the driver has not got.
        manifest = host.succeed(
            "systemd-run --machine=lani-services --quiet --pipe --wait --collect "
            "/run/current-system/sw/bin/cat /etc/lani-health-manifest.json"
        )
        services = json.loads(manifest.strip())["services"]
        assert set(services) == {"example", "nextcloud"}, f"unexpected manifest: {services}"
        assert services["nextcloud"]["tls"] is True
        assert services["example"]["subdomain"] == "example"

    with subtest("the host resolves and forwards the .local names"):
        # nat mode: the host stands in, since mDNS does not cross the link.
        host.succeed("getent hosts example.local")
        host.succeed("getent hosts nextcloud.local")

    with subtest("the example site answers through the proxy"):
        host.wait_until_succeeds(
            "curl -fsS http://example.local/ | grep -q 'It works'", timeout=180
        )

    with subtest("nextcloud answers through the proxy"):
        host.wait_until_succeeds(
            # Generous: Nextcloud's first-run setup took 27s on an idle machine and 283s
            # on a loaded one, so a tight bound here is just a flaky test.
            "curl -fsS -L http://nextcloud.local/login | grep -qi nextcloud",
            timeout=900,
        )

    with subtest("nextcloud is also served over TLS"):
        # Self-signed, hence -k. Vaultwarden depends on this path working.
        host.wait_until_succeeds(
            "curl -fsSk -L https://nextcloud.local/login | grep -qi nextcloud", timeout=300
        )

    with subtest("backend ports are not exposed, only the proxy"):
        # An earlier platform implementation opened every backend port to the LAN.
        host.fail("curl -fsS --max-time 5 http://nextcloud.local:8080/")

    with subtest("the admin password was generated on the host, not baked into the store"):
        host.succeed("test -s /var/lib/lani/nextcloud-admin-pass")
        host.succeed("test \"$(stat -c %a /var/lib/lani/nextcloud-admin-pass)\" = 600")
  '';
}
