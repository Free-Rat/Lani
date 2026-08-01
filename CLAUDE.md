# Lani — notes for coding agents

A declarative homelab platform for NixOS. Start with [README.md](README.md) for what it
is and [docs/architecture.md](docs/architecture.md) for how it fits together; this file
covers the things that are easy to get wrong.

## Working here

```sh
nix develop          # dev shell
nix fmt              # nixfmt, shfmt, shellcheck, prettier — run before committing
nix flake check      # evaluation, formatting, catalog consistency, VM tests
nix run .#vm         # boot the whole stack; the fastest way to see a change work
```

`nix flake check` boots real VMs and wants KVM. On a machine without it, the cheap checks
are still worth running:

```sh
nix build .#checks.x86_64-linux.catalog-consistency
nix eval .#nixosConfigurations.lani-vm.config.system.build.toplevel.drvPath
```

## Two names that look alike

- `lani.services.<name>` — a **publish declaration**, read by the platform module. Catalog
  modules set it. Generates the vhost, the mDNS name, the firewall rule, the health entry.
- `lani.serviceHost.*` — how **this host** runs the services container: which catalog
  modules to activate, bridge or nat, bind mounts.

Different evaluations, same prefix. Getting these confused is the most common mistake in
this repository.

## Things that will bite

**Nix strips the common indentation of an indented string.** If a heredoc's terminator is
not at the shallowest indentation level in the block, it comes out indented and bash never
terminates the heredoc — silently swallowing the rest of the script. This happened in the
avahi activation script and it took a while to find. Prefer `environment.etc` over
activation scripts writing heredocs.

**`writeShellApplication` runs shellcheck at build time and adds `set -euo pipefail`.**
Scripts written for `set -uo pipefail` need reviewing before being embedded in one.

**A `while read` on the right of a pipe runs in a subshell.** `exit 1` inside it exits
only the subshell. That is how the CI health check passed unconditionally for a while
despite looking like it was testing something. Use process substitution:
`done < <(printf '%s\n' "$x")`.

**Backends bind `127.0.0.1`, always.** The platform owns the firewall and the proxy.
There is a test asserting a backend port is unreachable.

**Do not reference `pkgs.claude-code` unconditionally.** It is unfree. The agent launchers
are built from an attrset whose entries are only forced when the agent is listed in
`lani.shell.agents`, which is what keeps a clean checkout building without an unfree
configuration. Keep it that way.

**No personal data in the repository.** No usernames, hostnames, domains, timezones,
locales or keys. Everything site-specific is an option with a neutral default. Before
committing:

```sh
git grep -nE '/home/[a-z]+|Europe/|ssh-(ed25519|rsa) AAAA'
```

## Adding a catalog service

Three files, and `nix flake check` fails if they disagree:
`catalog/modules/<name>/module.nix`, `catalog/modules.nix`, `catalog/catalog.nix`.
Full guide: [docs/catalog.md](docs/catalog.md).

## Conventions

- Conventional-commit prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.
- Every new option needs a `description` and a `type`. Somebody will read it with no other
  context.
- Comment _why_, not _what_. The comments around the nspawn cgroup workarounds are the
  reason anyone can maintain them.
