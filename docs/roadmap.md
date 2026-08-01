# Roadmap

Where Lani is, and what would make it the thing described in
[the README](../README.md). Framed around the work in the
[NLnet](https://nlnet.nl/) Fediversity application, since that is what funds it.

## Done

- **The declarative platform.** Declare a service, get a reverse proxy, an mDNS name,
  TLS, firewall rules and a health-manifest entry.
- **The service catalog**, as a standalone flake, with eight services.
- **The test loop.** Build, boot in a throwaway container, health-check every declared
  service, merge on green.
- **Parallel agent work.** One worktree and one file per feature, with a shared file
  designed so conflicts stay trivial.
- **Runs on hardware you have.** x86_64 and aarch64; a NixOS host, a Debian host via
  `machinectl`, or a QEMU VM with one command.
- **Tested in CI.** NixOS VM tests covering container boot, service health, and the
  security default that keeps the web terminal off the network.

## Next

### Validate generated configuration before showing it to anyone

The single highest-value piece. Every attribute path an agent produces gets checked
against the live NixOS option tree — via `nixos-option`, `manix`, or evaluating
`lib.evalModules` — before a diff is displayed. Models produce plausible Nix referencing
options that do not exist; catching that at generation time turns a failed rebuild into a
retry the user never sees.

### Retrieve only the relevant option subtree

The option tree does not fit in a context window, and stuffing it in makes accuracy worse.
The agent needs to fetch `services.navidrome.*` and not the other several thousand option
namespaces. Doing that well means inferring relevance from the request before the answer
is known.

### Self-correction for small models

A model small enough to run on the hardware in question is much worse at structured
generation than a hosted one. The loop — generate, validate, feed the errors back,
regenerate — trades latency for correctness, and is the difference between "needs a cloud
API" and "stays on your machine". Which is the entire premise.

### A rollback watchdog

`nixos-rebuild test` applies changes live without persisting them, which is the right
primitive. What is missing is the safety net: if the agent breaks sshd or networking
during the test window, the machine is unreachable until someone physically goes to it. A
watchdog that reboots into the previous generation unless success is confirmed within N
seconds closes that.

### Security validation of generated configuration

An agent should not be able to produce a configuration that quietly exposes something.
Automated checks on the resulting closure: known CVEs, firewall rules that bind `0.0.0.0`
unexpectedly, secrets that ended up in the store.

### Benchmarks worth publishing

Which locally-runnable models produce valid NixOS configuration, at which sizes, with what
retry budget. Nobody has this data and everybody choosing a local model wants it.

## Later

- **A verified plugin marketplace.** The catalog is already a separate flake with a
  consistency check; the missing pieces are deterministic testing of community
  contributions and a way to trust one you did not write.
- **Multi-node.** Several machines under one declarative configuration.
- **Backup and restore** as a first-class part of the platform rather than a service.

## Contributing to any of it

Issues and pull requests are welcome, and adding a catalog service is a genuinely small
first contribution — one file. See [catalog.md](catalog.md).
