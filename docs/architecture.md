# Architecture

Lani splits into three things that can each be used without the others: a **platform**
that publishes services, a **catalog** of services to publish, and an **agent workbench**
with a test loop that writes and verifies configuration. This document explains what each
one does and why the seams are where they are.

## The platform

`nix/platform/` is the piece that earns its keep. It takes declarations like this:

```nix
lani.services.nextcloud = {
  subdomain = "nextcloud";
  port      = 8080;
  tls       = true;
};
```

and generates, per service:

| Generated                                                            | Why it is generated rather than written                                                  |
| -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| an nginx vhost at `<subdomain>.local` proxying to `127.0.0.1:<port>` | every service needs one and they are identical apart from two values                     |
| an mDNS A record for that name on the live address                   | avahi publishes its own hostname and nothing else, so each name needs an explicit record |
| an mDNS service advertisement                                        | so the service shows up in network browsers                                              |
| firewall rules for 80, and 443 when anything wants TLS               | and _not_ for the backend port, which is the point of having a proxy                     |
| an entry in `/etc/lani-health-manifest.json`                         | so CI can check a service it was never told about                                        |
| a self-signed certificate, when `tls = true`                         | the web vault in a password manager will not run without a secure context                |

The manifest is the important one. It is the contract between "what is declared" and "what
gets verified": the health check reads it and tests whatever it finds, so adding a service
never means updating a test. When that manifest is missing, the health check fails loudly
rather than passing vacuously.

`nixosModules.platform` works on its own. If all you want is "put these five services
behind a proxy with proper names", you never need the rest of Lani.

### Why mDNS and not a real domain

A home network has no DNS you control and no certificate authority that will vouch for
`nextcloud.local`. mDNS gives you working names with zero configuration on any device made
in the last fifteen years, at the cost of self-signed certificates and one browser warning
per service. Services that need to be reachable from outside set `publicDomain`, which
adds a second vhost with a real Let's Encrypt certificate.

mDNS is link-local. That is the single constraint that shapes the network design below.

## Two containers

**`lani-shell`** is the workbench: coding agents, the session TUI, the web terminal, the
`lani` CLI. It shares the host's network namespace — no veth, no NAT, everything it
listens on appears on the host's own addresses. That is why its sshd is on 2222.

**`lani-services`** is the product: the platform plus whichever catalog services you
enabled. It has its own network namespace and, in bridge mode, its own DHCP lease on your
LAN.

They are separate because they fail differently. The workbench holds an encrypted home
full of credentials and agent state, and it is where things get broken on purpose. The
services container is re-imported wholesale on every deploy and holds nothing that matters
— everything persistent lives on the host and is bind-mounted back in.

The system inside the workbench is defined once, in `nix/shell-system.nix`, and used both
as a NixOS container and as a standalone rootfs tarball for hosts that do not run NixOS.

### bridge or nat

`lani.serviceHost.networking` picks how the services container reaches the network.

**`bridge`** puts it on your LAN with an address of its own. This is what you want on a
real host: mDNS is link-local, so `nextcloud.local` only resolves from your phone if the
container is genuinely on the same link. It needs a bridge on the host, which means taking
the address off your NIC and moving it to the bridge — do that from a local console the
first time.

**`nat`** gives it a point-to-point link to the host, with forwarding. Nothing on the LAN
sees it and mDNS does not propagate, so the host stands in: it resolves the `.local` names
itself via `/etc/hosts` and forwards 80 and 443 inward. It needs nothing from your network,
which is why the demo VM and the test suite use it.

## The test loop

```
agent (in lani-shell)                 host                      throwaway container
        │
        │ edits modules/<feature>.nix on a worktree
        │ nix build .#tarball
        │
        │ writes <id>.tar.xz to /var/lib/lani-ci/queue/
        │ writes <id>.req      ← last, on purpose
        │                              │
        │                    path unit fires
        │                              │  machinectl import-tar
        │                              ├─────────────────────────▶ boots
        │                              │
        │                              │  read the health manifest,
        │                              │  check every service listens
        │                              │  and answers through the proxy
        │                              │◀────────────────────────
        │                    writes results/<id>.json
        │◀─────────────────────────────┘
        │
        │ green? merge the branch.  red? report why.
```

The `.req` marker is written after the tarball for a reason: the host watches for `*.req`,
so writing it last is what stops a half-copied image being picked up.

The queue is drained serially. Two test containers would want the same machine name and
the same bridge.

### Parallel work

Several agents work at once, one git worktree each, one file each under `modules/`. The
only shared file is `modules/default.nix`, and the rule is that a feature adds exactly one
import line to it — so the worst case when two features land together is an add/add
conflict on adjacent lines, which resolves itself. Put logic in that file and simultaneous
features start conflicting for real.

`configuration.nix`, `flake.nix` and `flake.lock` are frozen during feature work for the
same reason.

## Where state lives

Nothing that matters is inside a container.

| Path on the host       | What                                                                                                      |
| ---------------------- | --------------------------------------------------------------------------------------------------------- |
| `/var/lib/lani/`       | generated credentials and persistent service data, bind-mounted in read-only or read-write as appropriate |
| `/var/lib/lani-ci/`    | the queue, results, logs and status the dashboard reads                                                   |
| `/var/lib/lani-shell/` | the LUKS image and its key                                                                                |
| `lani.repoPath`        | the services repository agents edit                                                                       |

Credentials are generated on the host at 0600 and never enter the Nix store, which is
world-readable. What each service needs is declared in `catalog/host.nix` rather than
hardcoded, so the mechanism is the same for a service nobody has written yet.

## Repository layout

| Path                   | What lives there                                              |
| ---------------------- | ------------------------------------------------------------- |
| `nix/platform/`        | the service platform                                          |
| `nix/modules/`         | the `lani.*` module set: both containers, LUKS home, CI queue |
| `nix/shell-system.nix` | the workbench system, shared by the container and the image   |
| `nix/vm.nix`           | the demo VM                                                   |
| `catalog/`             | the service catalog. Its own flake                            |
| `cli/`                 | the `lani` command                                            |
| `ci/`                  | health check and browser check                                |
| `templates/`           | `nix flake init` starting points                              |
| `host-tools/`          | deploying onto a host that is not running NixOS               |
| `tests/`               | NixOS VM tests, wired into `flake.checks`                     |
