# Deploying to a host that is not running NixOS

You need this only if the target machine cannot run NixOS itself — the original deployment
is a Raspberry Pi on Debian. On a NixOS host, use `nixosModules.default` and
`nixos-rebuild switch`; it does everything here and more, declaratively.

The idea: build a NixOS system into a portable rootfs tarball, import it with
`machinectl`, and run it under `systemd-nspawn`. The host needs systemd and
`systemd-container`; it does not need Nix.

## Deploying

```sh
lani-deploy --target pi.local --flake .#tarball
```

If the target is too slow to build for itself, build somewhere else — a machine with
binfmt emulation configured for the target architecture:

```sh
lani-deploy --target pi.local --build-host builder.local
```

`--help` lists the rest. Everything site-specific is an argument; the script knows nothing
about your network.

## Building an image with your own keys

The tarball in this flake has no SSH keys in it, on purpose — a published image with a key
baked in is a backdoor. Build your own:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.lani.url = "github:Free-Rat/Lani";

  outputs = { nixpkgs, lani, ... }:
    let
      system = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          lani.nixosModules.shellImage
          { lani.authorizedKeys = [ "ssh-ed25519 AAAA... you@laptop" ]; }
        ];
      };
    in {
      packages.aarch64-linux.tarball = system.config.system.build.tarball;
    };
}
```

Then `lani-deploy --target pi.local --flake .#tarball`.

## What lands on the host

| Path                                                                    | What it is                                  |
| ----------------------------------------------------------------------- | ------------------------------------------- |
| `/etc/systemd/nspawn/lani-shell.nspawn`                                 | container settings and bind mounts          |
| `/etc/systemd/system/systemd-nspawn@lani-shell.service.d/override.conf` | the drop-in below                           |
| `/usr/local/lib/lani/lani-home`                                         | LUKS unseal and seal helper                 |
| `/etc/systemd/system/lani-home.service`                                 | runs it before the container starts         |
| `/var/lib/lani-shell/home.key`                                          | generated once, root-only. **Back this up** |
| `/var/lib/machines/lani-shell`                                          | the imported rootfs                         |

**Edit `lani-shell.nspawn` before deploying.** Its bind-mount paths are examples — where
your services repository lives, and which account name matches your `lani.user`.

## Two workarounds worth understanding

Both live in `lani-shell-override.conf`, and both will look arbitrary until they bite you.

**`SYSTEMD_NSPAWN_UNIFIED_HIERARCHY=1`.** nspawn works out which cgroup layout to use by
looking for `/usr/lib/systemd/systemd` in the image. A NixOS image does not have that path
— systemd is in the store — so nspawn guesses the legacy layout, and the container's
modern systemd refuses to boot into it: _"Detected unsupported legacy cgroup hierarchy"_.
Forcing unified fixes it.

**The `ExecStart` reset.** The stock template passes `-U` (private users) and
`--network-veth`. Both are dropped: without user namespacing, uids match on both sides of
a bind mount, so a file written inside the container is owned by the same account outside;
and sharing the host's network namespace means no bridge setup on a host that may not run
systemd-networkd at all.

There is a third, in `lani-deploy` itself: NixOS images mark `/var/empty` immutable, so a
plain `rm -rf` of an old machine directory fails partway and leaves the container removed
but not re-imported — that is, down. It clears the immutable bits first.

## The CI queue

`lani-ci.path` and `lani-ci.service` are the host side of the test loop: a path unit
watches `/var/lib/lani-ci/queue/*.req` and drains the queue serially. On a NixOS host
`nix/modules/ci.nix` sets this up for you. On a non-NixOS host, install the two units and
put the orchestrator at `/usr/local/lib/lani/lani-ci` — build it with
`nix build .#nixosConfigurations.lani-vm.config.systemd.services.lani-ci` and copy the
`ExecStart` script out, or write the equivalent by hand.
