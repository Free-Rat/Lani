# The agent loop

The goal is: you say "install a music server", and a correct NixOS configuration appears,
is tested, and either deploys or is rejected with a reason. This document describes what
actually happens today, and is explicit about which parts are not finished.

## What runs

Lani does not contain an LLM client. Agents are ordinary binaries from nixpkgs, run as
subprocesses:

| Agent             | Licence    |                                          |
| ----------------- | ---------- | ---------------------------------------- |
| `pi-coding-agent` | MIT        | default                                  |
| `opencode`        | MIT        | default                                  |
| `claude-code`     | **unfree** | opt-in via `lani.shell.enableClaudeCode` |

The default set is free software so a clean checkout builds with no unfree configuration.
That is a deliberate constraint, not an accident: a platform whose documented workflow
requires a proprietary binary is not one you can hand to someone else.

`lani.shell.systemPrompt` is injected into every session, so how the agents behave is part
of your NixOS configuration rather than a file somebody edited once on the machine.

## The loop, concretely

```
you                     agent                     host CI
 │
 │ lani modules use jellyfin
 │────────────────────────▶
 │                          creates a worktree on feat/jellyfin
 │                          copies the catalog module in
 │                          adds one import line
 │                          commits
 │                          ./request-test.sh
 │                          ──────────────────────▶
 │                                                 boot a throwaway container
 │                                                 read the health manifest
 │                                                 check every service listens
 │                                                 and answers through the proxy
 │                          ◀──────────────────────
 │                          green: merge the branch
 │                          red:   report why, do not merge
 │◀────────────────────────
 │ sudo nixos-rebuild switch
```

Three things make this safe rather than hopeful:

**The test target is disposable.** The candidate boots as an ephemeral nspawn container
that is destroyed either way. A broken configuration never touches the running system.

**The check is generated, not written.** The platform emits
`/etc/lani-health-manifest.json` from the service declarations, and the health script
tests whatever it finds there. Nobody has to remember to add a test, and nobody can forget.

**Merging is gated on the result.** `request-test.sh` merges the feature branch only on a
pass, and refuses even then if the main worktree has uncommitted work.

While it runs there is a live dashboard — phases, and the agent's own output streaming in
— on loopback port 9000.

## What is finished and what is not

**Finished.** The plumbing: scaffolding a feature branch, building it, queueing it,
booting it in isolation, health-checking every declared service, merging on green,
reporting on red. Several agents can work in parallel, one worktree each.

**Not finished.** The part where a model turns "install a music server" into correct Nix.

Today an agent is driven through a _known_ change — a catalog module that already exists.
Generating a novel module from a plain-English request is the open problem, and it is the
one the [NLnet](https://nlnet.nl/) application is about. It is hard for reasons that are
specific and worth stating:

**Models invent option names.** The NixOS option tree is enormous and an LLM will produce
Nix that looks entirely correct and references `services.foo.enableBar`, which does not
exist. The rebuild then fails on a typo. The fix is to validate every generated attribute
path against the live option tree before showing anyone a diff — this is a solved problem
in principle and unimplemented here.

**The option tree does not fit in a context window.** Sending all of it makes the model
worse, not better. The agent needs to retrieve only the subtree relevant to the request,
which means guessing what is relevant before you know what the answer is.

**Small models are much worse at this.** A 7B model that runs on the hardware someone
actually owns produces structured Nix far less reliably than a large hosted one. The way
out is iterative self-correction — generate, validate, feed the errors back, regenerate —
trading latency for correctness. That only works if validation is cheap and precise, which
takes us back to the first point.

**A successful rebuild is not a working system.** nginx starts fine while proxying to a
backend that returns 500. Hence the health manifest, which is the part that already works.

**`nixos-rebuild test` is not reversible if it breaks the network.** Applied changes are
live but not persisted across reboot, which is the right primitive — but if the agent
breaks sshd during the test window, the machine is gone until someone walks over to it. A
watchdog that reboots into the previous generation unless the agent confirms success
within N seconds is designed and not built.

## Trust

The agent runs as `lani.user` in the workbench container, with write access to the
services repository and the ability to queue builds. Treat any model as untrusted input:

- Changes go through the health gate before they persist.
- The agent never edits `configuration.nix`, `flake.nix` or `flake.lock` — only files
  under `modules/`.
- Read the diff. The gate catches broken systems, not malicious ones.

That last line is the honest summary of where this is.
