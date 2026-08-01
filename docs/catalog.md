# Writing a catalog service

A service is one file. This is the whole of `catalog/modules/navidrome/module.nix`:

```nix
{ ... }:
{
  lani.services.navidrome = {
    subdomain   = "music";
    port        = 4533;
    description = "Navidrome music server";
  };

  services.navidrome = {
    enable = true;
    settings = {
      Address = "127.0.0.1";
      Port    = 4533;
      MusicFolder = "/var/lib/navidrome/music";
    };
  };
}
```

Two parts, always. The `lani.services.<name>` block tells the platform to publish it; the
rest is ordinary nixpkgs configuration.

## Adding one

Three files have to agree, and `nix flake check` fails if they do not:

1. `catalog/modules/<name>/module.nix` — the module
2. `catalog/modules.nix` — `<name> = ./modules/<name>/module.nix;`
3. `catalog/catalog.nix` — the metadata `lani modules list` shows

The consistency check compares the catalog's `subdomain` and `port` against what the
module actually publishes, and verifies the module registers itself under its own name.
That check exists because these drifted in practice: Uptime Kuma registered itself as
`status` while the catalog called it `uptime-kuma`, so the health manifest and the CLI
disagreed about what the service was called.

Metadata is duplicated between `catalog.nix` and the module on purpose — the CLI has to
list services without evaluating a NixOS system, which would take seconds.

## The declaration

| Option             | Default            |                                                                    |
| ------------------ | ------------------ | ------------------------------------------------------------------ |
| `subdomain`        | the attribute name | the name without `.local`                                          |
| `port`             | —                  | the loopback port your app listens on                              |
| `description`      | the attribute name | shown in the mDNS advertisement                                    |
| `tls`              | `false`            | also serve https, self-signed                                      |
| `default`          | `false`            | answers the container's raw address. At most one service           |
| `proxyWebsockets`  | `false`            | forward WebSocket upgrade headers                                  |
| `maxBodySize`      | `512m`             | `client_max_body_size` on the proxy                                |
| `publicDomain`     | `null`             | a real FQDN over Let's Encrypt. Needs `lani.acmeEmail`             |
| `extraVhostConfig` | `{}`               | merged into the generated vhost, for the cases nothing else covers |

Two of these are worth setting more often than people do:

**`proxyWebsockets`** — anything with live updates needs it: chat, dashboards, peer
discovery, playback sync. The failure without it is a page that loads perfectly and then
never updates, which is annoying to diagnose and trivial to prevent.

**`maxBodySize`** — nginx defaults to 1M, small enough that file uploads fail before the
application ever sees the request.

## Rules

**Bind the backend to `127.0.0.1`.** The platform owns the firewall and the proxy. An
earlier version of the platform opened every backend port alongside the proxy, which
defeated the point of having one; `services-health` now has a test asserting a backend
port is unreachable.

**Ship safe defaults.** No open registration, no default passwords, no anonymous write
access. If a service is only usable over TLS, set `tls = true` — browsers restrict the
Web Crypto API to secure contexts, so a password manager served over plain http loads and
then silently refuses to unlock.

**No personal data.** No locales, no timezones, no domain names, no email addresses. If a
service genuinely needs a region, read `config.lani.countryCode`, which is null by
default; Nextcloud does this for phone-number parsing.

**Stay in your own file.** One service, one directory.

## Persistent state and credentials

The services container is re-imported wholesale on deploy, so anything that must survive
lives on the host. Declare it in `catalog/host.nix`:

```nix
nextcloud = {
  # Random, generated once on the host at 0600, mounted read-only. Never in the store.
  secrets."/etc/nextcloud-admin-pass" = "nextcloud-admin-pass";

  # Created if absent, mounted read-write.
  state."/var/lib/nextcloud" = { dir = "nextcloud-data"; mode = "0700"; };
};
```

Only Nextcloud declares state today, and there is a caveat worth understanding before you
add more: nspawn runs without user namespacing here, so uids inside the container are host
uids, and NixOS assigns service uids dynamically unless they are declared. A persisted
directory can end up owned by the wrong account after an unrelated rebuild shifts a uid.
If you add state for a service, test a rebuild-and-restart cycle, not just a first boot.

## Reverse-proxying an app that ships its own nginx

Nextcloud is the awkward case, and the pattern generalises. Its own nginx server block has
to move off port 80, which the platform's proxy occupies, and it has to be told which Host
headers to trust:

```nix
services.nextcloud.hostName = "nextcloud-backend";   # not nextcloud.local
services.nginx.virtualHosts."nextcloud-backend".listen =
  lib.mkForce [ { addr = "127.0.0.1"; port = 8080; } ];

services.nextcloud.settings = {
  trusted_domains = [ "localhost" "nextcloud-backend" "nextcloud.local" ];
  trusted_proxies = [ "127.0.0.1" ];
  overwritehost   = "nextcloud.local";
};
```

The backend vhost name must not be the public name — two server blocks claiming
`nextcloud.local` is a configuration error.

## Testing it

```sh
nix flake check                    # consistency, formatting, the VM tests
nix run .#vm                       # after adding it to nix/vm.nix activeModules
```

On a real host, `lani modules use <name>` scaffolds a feature branch, builds it, boots it
in a throwaway container and health-checks it before merging.

## Using your own catalog

`catalog/` is a flake. Fork it, add your services, and point a host at it:

```nix
lani.catalog = inputs.my-catalog.nixosModules;
```

Nothing in Lani special-cases the bundled one — it is just the default.
