# codpiece agent guidance

This repository is the Workshop for the smallest useful piece of Codex: the
voice-only sidecar consumed by AgentVoice. Read CONTEXT.md, MAINTAIN.md, and
SCRATCHPAD.md before changing the fork, its gate, or its installer.

## Ownership

- MAINTAIN.md is the complete product and maintenance contract. The shared
  maintain skill reads its fixed sections by name; add within a section and do
  not rename one.
- SCRATCHPAD.md records delivered state and audited upstream state. It is not a
  second feature specification.
- scripts/reconcile-branches.sh rejects any local carry outside the exact active
  inventory, then delegates namespace mechanics to the shared maintain skill.
- scripts/bootstrap-branches.sh is the tested one-use path for creating the
  first carry and Integration under absence leases. Never recreate that
  transaction manually.
- scripts/install.sh is the sole consumer handoff. It builds one exact
  published Integration commit in a detached worktree and installs only the
  voice-sidecar binary. It must not rebase, publish, inspect pull requests, or
  decide which behavior remains carried.
- tests/validate.sh validates the Workshop machinery; the local-build,
  AgentVoice artifact, and ship gates are the blocking product authorities.

Codex implementation work lives in dedicated worktrees of
~/source/openai--codex, never in that bound checkout and never in this
Workshop. AgentVoice integration work lives in ~/code/agentvoice. The accepted
full Codex App-server run there is the behavioral oracle until the small
sidecar reproduces it.

## Feature work

An ordinary request to change the Codex voice sidecar is carried feature work
unless current upstream already satisfies the contract. The user does not need
to mention maintenance or branches.

Before implementation:

1. Read MAINTAIN.md section Features and extend the matching observable
   contract, or add a new mapped carry.
2. Develop the Codex implementation on the declared carry branch in a
   dedicated worktree based on current Main or its declared dependency.
3. Treat the Codex commit and the Workshop inventory commit as paired commits
   in the same requested unit of work. The repositories cannot share one Git
   commit, but neither half is optional.

Integration is the only consumer source. Never build AgentVoice from an
ambient carry branch or from the bound checkout.

## Product boundary

The permanent product is codex-voice-sidecar, not a mode of codex-app-server.
It owns realtime voice transport and an in-memory synthetic voice thread. Fx
owns workspace reasoning and work. Client-managed delegation is intrinsic and
cannot be switched off.

The sidecar must never create a Codex coding thread or turn, start MCP, touch a
workspace, launch a sandbox or tool process, write a rollout, or depend on the
full Codex core and App-server graph.

The active first milestone deliberately retains Codex subscription auth to
prove voice parity. The planned final authorization boundary is strict: Fx
owns the configured Codex provider authority. The sidecar then consumes a
bounded runtime lease and never logs in, reads Codex credential stores,
refreshes a token, rotates a refresh token, or persists authority.

## Working topology

Work directly on main in this Workshop. In ~/source/openai--codex, use one
dedicated worktree per carry and a separate scratch worktree for the exact
Integration composition. Inventory existing worktrees first and remove only
clean worktrees created by the current cycle.

Maintenance owns only Main, Integration, and the carries declared in
MAINTAIN.md. Every other fork head remains untouched. No branch is deleted or
moved under DELETEME/ without an explicit human decision naming it.

## Resource limits

This machine has already suffered severe memory pressure from unconstrained
Codex release builds. Every Rust build for this project uses at most two Cargo
jobs, release LTO disabled, one release codegen unit, stripped release symbols,
and a target directory on /Volumes/Scratch when it is available. Never launch
the full Codex suite,
parallel release builds, or an unconstrained workspace build.

Start with targeted debug tests. Build the one release binary only after those
tests pass. Follow upstream's order: run the targeted just test command, then
just fix -p codex-voice-sidecar, then just fmt, and do not rerun tests after
fix or format. Reap every process and worktree the gate starts.

## Validation and publication

Run:

~~~sh
tests/validate.sh
~~~

Product changes run all three exact gates in MAINTAIN.md: local build, immutable
AgentVoice artifact, and post-publication ship. A voice candidate is not
installable until the compact full-duplex scenario produces its required
evidence and audio recording and the ship receipt revalidates it.

Finished Workshop work is committed on main. Publication of the product fork
uses the exact leased Integration procedure in MAINTAIN.md. The consumer
installs only an exact full SHA after publication.
