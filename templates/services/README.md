# Lani services

This is the repository your agents edit. It defines the services container: one file per
feature under `modules/`, tested on real hardware before it is merged.

It lives at `lani.repoPath` on the host and is bind-mounted into the workbench container
at `/etc/nixos`.

## The rules

They exist so that several agents — or several people — can work at the same time without
tripping over each other, and they are also injected into the agents' system prompt.

1. **One feature = one worktree = one branch = one file** under `modules/`.
2. **Never edit `configuration.nix`, `flake.nix` or `flake.lock` on a feature branch.**
   Those are shared; changing them turns parallel work into merge conflicts.
3. **`modules/default.nix` gets exactly one new line** — the import of your module.
   Nothing else. That way two features colliding produce an add/add conflict on adjacent
   lines, which resolves itself.
4. **Everything your feature needs goes in your own file**: the service, its firewall
   ports, its helper units, its `lani.services.<name>` declaration.
5. **Test before merging.** `./request-test.sh` is the gate.

## Adding a service

```sh
git worktree add ../lani-services.worktrees/jellyfin -b feat/jellyfin
cd ../lani-services.worktrees/jellyfin
```

Write `modules/jellyfin.nix`, add its one import line to `modules/default.nix`, commit,
then:

```sh
./request-test.sh
```

That builds the image, hands it to the host's CI queue, waits for the host to boot it as
a throwaway container and health-check every declared service, and merges the branch if
everything is green.

Or skip the manual part entirely — `lani modules use jellyfin` does the scaffolding, runs
an agent against it, and shows you a live dashboard.

## The testing ladder

| Layer      | What it catches                                       | Where                                               |
| ---------- | ----------------------------------------------------- | --------------------------------------------------- |
| 1. Build   | Evaluation errors, bad option names, missing packages | in the workbench, `nix build`                       |
| 2. Health  | Services that build but do not start, or answer 500   | on the host, in a throwaway container               |
| 3. Browser | Pages that return 200 and are still broken            | `ci/browser-check.mjs` against the reported address |

Layer 2 is the one that matters, and it is automatic: the platform writes
`/etc/lani-health-manifest.json` listing every declared service, and the health check
reads it. Add a service and it is checked — there is no test to update.

## Deploying

Merging does not deploy. When you are happy:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#<your-host>
```
