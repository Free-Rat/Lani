# Lani

**A home server you describe in a sentence, on a foundation that can prove it works.**

Lani is a declarative homelab platform for NixOS. Declare a service and you get a reverse
proxy, a `.local` name, TLS, a firewall rule and a health check — generated, not
configured. An LLM agent runs on the machine itself, writes the NixOS configuration for
what you asked for, tests it in a throwaway container, and merges it only if it comes up
green. Everything stays on your hardware.

> Early days. The declarative platform and the test loop work today; the agent loop is a
> working proof of concept rather than a finished product. See [Status](#status).

## Try it in one command

```sh
nix run github:Free-Rat/Lani#vm
```

That boots the whole stack in a throwaway QEMU VM — no Raspberry Pi, no second machine,
nothing installed on yours. Once it is up:

| Reach it at                                              | What you get                                          |
| -------------------------------------------------------- | ----------------------------------------------------- |
| `http://localhost:8080/`                                 | the example site, through the generated reverse proxy |
| `curl -H 'Host: nextcloud.local' http://localhost:8080/` | Nextcloud, installed unattended                       |
| `http://localhost:7681/`                                 | the web terminal and session manager                  |

## What "declare a service" means

This is a complete service module. There is no second file.

```nix
{ ... }:
{
  lani.services.navidrome = {
    subdomain = "music";
    port = 4533;
  };

  services.navidrome = {
    enable = true;
    settings = { Address = "127.0.0.1"; Port = 4533; };
  };
}
```

From the four lines at the top, Lani generates:

- an nginx reverse-proxy vhost at `music.local`
- an mDNS record so that name resolves from your phone and your laptop
- a firewall rule for the proxy — and none for the backend, which stays on loopback
- an entry in `/etc/lani-health-manifest.json`, which is what CI verifies

Add TLS with `tls = true`, websockets with `proxyWebsockets = true`, a real certificate on
a public name with `publicDomain`. Eight services ship in the catalog: Nextcloud,
Vaultwarden, Jellyfin, Forgejo, Navidrome, Uptime Kuma, Pairdrop, and a static example.

## How it fits together

```
  ┌─ your NixOS host ──────────────────────────────────────────────┐
  │                                                                │
  │   lani-shell                      lani-services                │
  │   ┌──────────────────────┐        ┌──────────────────────────┐ │
  │   │ coding agents        │        │ nginx reverse proxy      │ │
  │   │ session TUI + web    │        │ mDNS  ·  TLS             │ │
  │   │ the `lani` CLI       │        │ health manifest          │ │
  │   │                      │        │ ┌──────┐ ┌──────┐        │ │
  │   │ edits ───────────────┼──┐     │ │ next │ │ jell │  ...   │ │
  │   └──────────────────────┘  │     │ │cloud │ │ yfin │        │ │
  │            │                │     │ └──────┘ └──────┘        │ │
  │            │ enqueues       │     └──────────────────────────┘ │
  │            ▼                ▼              ▲                   │
  │      ┌───────────┐   ┌──────────────┐      │ deploy            │
  │      │ CI queue  │──▶│ throwaway    │──────┘                   │
  │      │           │   │ container    │  health checks, then     │
  │      └───────────┘   └──────────────┘  merge if green          │
  └────────────────────────────────────────────────────────────────┘
```

Two containers, with different jobs. **`lani-shell`** is the workbench: agents, a terminal
you can reach from a browser, and the services repository they edit. **`lani-services`**
is what they build: the platform and your actual services, on their own LAN address so
`.local` names resolve properly.

Between them sits a file queue. An agent finishes a change and enqueues a built image; the
host boots it as a throwaway container, checks every service in the manifest answers, and
reports back. Only then does the branch merge. A broken change never reaches the running
system.

## Install it for real

```sh
nix flake init -t github:Free-Rat/Lani#host
```

Edit `configuration.nix` — at minimum your SSH key and which services you want — then:

```sh
sudo nixos-rebuild switch --flake .#myhost
```

Or add the module to a flake you already have:

```nix
{
  inputs.lani.url = "github:Free-Rat/Lani";

  outputs = { nixpkgs, lani, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        lani.nixosModules.default
        {
          lani = {
            enable = true;
            authorizedKeys = [ "ssh-ed25519 AAAA... you@laptop" ];
            serviceHost.activeModules = [ "nextcloud" "vaultwarden" ];
          };
        }
      ];
    };
  };
}
```

`lani.catalog` defaults to the catalog in this repository, so nothing else is required.

**Not running NixOS on the target?** `host-tools/lani-deploy` builds a portable rootfs and
imports it with `machinectl` onto any systemd host — that is how this runs on a Raspberry
Pi under Debian. Run it with `--help`.

**Only want the service platform?** `nixosModules.platform` is the reverse proxy, mDNS,
TLS and health manifest on their own, usable on any NixOS host with no containers and no
agent. The catalog is a flake in its own right too: `github:Free-Rat/Lani?dir=catalog`.

## Security, briefly

**The web terminal is an unauthenticated shell.** Anyone who can load the page gets one.
It binds `127.0.0.1` and does not open the firewall; reach it with
`ssh -L 7681:127.0.0.1:7681 <host>`. Setting
`lani.shell.webTerminal.listenAddress = "0.0.0.0"` publishes that shell to every device on
your LAN, so do it only behind a VPN or an authenticating reverse proxy.

Passwordless `sudo` is off by default (`lani.security.passwordlessSudo`), SSH is key-only,
and generated credentials are created on the host at mode 0600 rather than in the Nix
store, which is world-readable.

Lani assumes a trusted LAN. It is a home platform, not a hardened internet-facing one.
`.local` services get self-signed certificates — the browser warning is expected.

The agent can change your system: that is the point. Changes go through `nixos-rebuild
test` and the health gate before they persist, and the agent only edits files under
`modules/`. Review the diff — the gate catches broken systems, not malicious ones.

## Status

Working today:

- the declarative service platform, and the eight-service catalog
- the CI loop: build, boot a throwaway container, health-check, merge or reject
- both containers, the CLI, the web terminal, and the demo VM
- NixOS VM tests covering all of it, in CI

Proof of concept:

- the agent loop. An agent can be pointed at a feature branch and driven through the test
  cycle, but generating a correct NixOS configuration from a plain-English request is
  still the hard, unfinished part — validating generated options against the real option
  tree, keeping the model's context small enough to be accurate, and doing it with a model
  small enough to run on the hardware in question.

That last item is what this project is actually about, and what the
[NLnet](https://nlnet.nl/) grant application funds. The roadmap is in
[docs/roadmap.md](docs/roadmap.md).

## Documentation

| Document                                     | Covers                                              |
| -------------------------------------------- | --------------------------------------------------- |
| [docs/architecture.md](docs/architecture.md) | how the pieces fit, and why they are split that way |
| [docs/catalog.md](docs/catalog.md)           | writing a service module                            |
| [docs/agent-loop.md](docs/agent-loop.md)     | what the agent actually does                        |
| [docs/roadmap.md](docs/roadmap.md)           | what is next                                        |
| [CLAUDE.md](CLAUDE.md)                       | getting set up, and the things that bite            |

## Licence

[AGPL-3.0](LICENSE).
