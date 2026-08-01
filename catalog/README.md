# Lani service catalog

NixOS modules for self-hosted services, each one a reverse-proxied, mDNS-named, health-
checked endpoint from a four-line declaration.

This is a flake in its own right. You do not need the rest of Lani to use it — though you
do need something providing the `lani.services` option, which is
`github:Free-Rat/Lani#nixosModules.platform`.

```nix
{
  inputs.lani.url = "github:Free-Rat/Lani";
  inputs.lani-catalog.url = "github:Free-Rat/Lani?dir=catalog";
}
```

```nix
imports = [
  lani.nixosModules.platform
  lani-catalog.nixosModules.navidrome
  lani-catalog.nixosModules.jellyfin
];
```

On a full Lani host you never do this — `lani.serviceHost.activeModules = [ "navidrome" ]`
is the same thing, and `lani.catalog` already points here.

## What is in it

| Service     | Name                | Notes                                                |
| ----------- | ------------------- | ---------------------------------------------------- |
| Nextcloud   | `nextcloud.local`   | TLS, the default vhost, 2G uploads                   |
| Vaultwarden | `vaultwarden.local` | TLS required — see below                             |
| Jellyfin    | `jellyfin.local`    | websockets for playback sync                         |
| Forgejo     | `git.local`         | registration disabled by default                     |
| Navidrome   | `music.local`       | Subsonic-compatible                                  |
| Uptime Kuma | `status.local`      | websockets                                           |
| Pairdrop    | `drop.local`        | websockets, stateless                                |
| Example     | `example.local`     | a static page; the smallest module, and a smoke test |

## Defaults you should know about

**Vaultwarden is served over TLS and cannot sensibly be otherwise.** Browsers only expose
the Web Crypto API in a secure context, so over plain http the web vault loads and then
refuses to unlock. The certificate is self-signed, so expect one browser warning.

**Forgejo ships with registration disabled.** Create your account through the first-run
wizard, then invite people from the admin panel. A forge with open registration is a forge
anyone who can reach it can push to.

**Nextcloud's admin password is generated on the host** at
`/var/lib/lani/nextcloud-admin-pass`, mode 0600, and bind-mounted read-only. It is never
in git and never in the Nix store.

**Every backend binds `127.0.0.1`.** The platform's reverse proxy is the only public door,
and the firewall reflects that: 80, 443, and mDNS. Nothing else.

## Adding a service

One file. See [docs/catalog.md](../docs/catalog.md) for the full guide.

Three files have to agree — the module, `modules.nix`, and `catalog.nix` — and
`nix flake check` fails if they do not.
