# codpiece fork maintenance

This repository delivers and maintains the smallest useful piece of
openai/codex: a standalone realtime voice sidecar used by AgentVoice with Fx
as its orchestrator and, ultimately, its only authorization authority. The
shared maintain skill runs a maintenance cycle from this file; this file is
the whole of what that skill knows about codpiece.

## Purpose

Keep a published Integration branch of possibilities/codex containing a
small, auditable codex-voice-sidecar. It must reproduce the accepted native
Codex voice collaboration while starting zero Codex coding turns, then remove
its independent login and use the Codex provider authority configured in Fx.

The fork exists to retain Codex's strongest realtime speech behavior without
bringing the Codex coding runtime into an Fx-based system or spending a second
subscription authorization on an invisible paired coding agent.

What this fork is not:

- a smaller general Codex CLI or App-server;
- a second coding agent;
- a distribution of all Codex realtime versions or transports;
- a place to patch unrelated Codex behavior;
- a credential store or interactive login surface;
- a replacement for AgentVoice, Fx, or the accepted evaluation harness.

The full Codex App-server remains a behavioral oracle only. The permanent
binary is a new standalone crate and protocol façade with a deliberately
smaller compile and runtime boundary.

## Upstream

- Bound checkout: ~/src/codex.
- Upstream: openai/codex on remote origin.
- Product fork: possibilities/codex on remote fork.
- Upstream branch: main. The local and fork Main mirrors contain no downstream
  commits.
- The accepted historical oracle is Codex
  430d26b543b219049192de559987b8cf506efacf with
  ~/code/agentvoice/patches/codex-client-managed-handoffs.patch. It is evidence,
  not the implementation base.
- Upstream commit b2b94fe755 extracted realtime behavior into a standalone
  codex-realtime crate and is useful design evidence. Current upstream later
  collapsed parts of that boundary; neither historical shape is a dependency.
- Read the complete upstream AGENTS.md hierarchy that applies to every file
  changed in a product worktree.
- The fork currently contains thousands of unrelated historical heads.
  Maintenance reports and preserves every one. It owns only Main, Integration,
  and the carries declared below.
- No upstream offer is currently planned. The voice-only product, intrinsic Fx
  delegation, and Fx-owned authority are downstream system boundaries. A
  generally useful extraction may be offered later only as fresh upstream-shaped
  work after explicit human approval.
- Landed means current openai/codex main satisfies an inventory contract at the
  same dependency and runtime boundary, confirmed by reading and exercising
  that code. A merged request, renamed crate, or similar API is evidence but
  not sufficient.

## Branch model

- Mirror branch: main, always the exact openai/codex:main commit locally and on
  the fork.
- Integration branch: integration, every currently required carry composed in
  dependency order. It is the only ref the installer builds and is nobody's
  review context.
- Composition: carry heads.
  - carry/voice-sidecar is based on current Main.
- Each carry head is durable and published. A head contains the dependency
  below it but owns only its commits above that predecessor. Every carry head
  must be an ancestor of published Integration.
- The initial bootstrap is a one-use, executable exception because the fork
  has no Integration or carry refs. After the exact voice candidate has both a
  current private local-build receipt and an accepted AgentVoice artifact
  receipt chained to that exact local receipt hash, run
  `scripts/bootstrap-branches.sh --check`, inspect its three-ref plan, then run
  `scripts/bootstrap-branches.sh --apply`. It snapshots upstream Main and every
  fork head, requires Integration and carry/voice-sidecar to be absent,
  validates the full receipt chain and AgentVoice artifact hashes, and
  atomically pushes only upstream Main, the gated voice carry, and Integration.
  The fork-Main lease is its observed exact SHA; both new-ref leases require
  absence. A moved Main, appearing target, failed receive hook, ancestry error,
  or missing receipt moves none of them. Normal shared reconciliation is used
  forever after. If the remote transaction succeeds but local tracking setup is
  interrupted, rerunning `--check` reports `REPAIR-LOCAL` and rerunning
  `--apply` idempotently binds only the already exact remote refs.
- Publication authority covers the exact gated Integration commit and the
  declared namespace reconciliation required by the shared maintain skill.
  It never covers unrelated heads.
- Deletion marker prefix: DELETEME/. Creating, moving, or removing a marker
  requires an explicit human decision naming the original branch. No age,
  ownership, inactivity, or absence from this inventory implies deletion.
- Open pull-request heads are preserved but not exact-head validated by this
  Workshop. The Workshop has no active upstream offer.
- Keep rerere enabled. A recorded resolution is evidence only; every upstream
  interaction is reread and regated.
- scripts/reconcile-branches.sh enforces the exact active carry set and phase
  composition before delegating namespace mechanics to the shared skill.
- Supervision: `scripts/reconcile-branches.sh --configure-supervision`
  converges this model into the bound checkout's own `supervisor.*` git
  config, which is where advisory tools read it — `/tend` judges a worktree
  against the integration branch and never proposes removing a carry head's
  worktree. It is derived state, not a second declaration:
  `--check-supervision` verifies it, and that this section still names these
  branches.

## Features

Absence is work. Every product change updates this inventory in a paired
Workshop commit during the same requested unit of work.

| Carry | Dependency | Required behavior |
| --- | --- | --- |
| carry/voice-sidecar | Main | Standalone V3 voice transport and narrow compatibility protocol with zero coding infrastructure. |
| carry/fx-authorization | carry/voice-sidecar | Fx is the sidecar's only authorization authority, over one persistent framed channel on inherited descriptor 3. |

### Standalone V3 voice sidecar

- carry/voice-sidecar.
- Build one binary named codex-voice-sidecar. It must not depend on
  codex-app-server, codex-core, codex-app-server-protocol, codex-protocol, MCP,
  tool, sandbox, rollout, storage, or workspace-worker crates.
- Expose only the App-server-compatible JSON-RPC surface AgentVoice needs:
  initialize, initialized, thread/realtime/listVoices, thread/start,
  thread/realtime/start, thread/realtime/appendSpeech,
  thread/realtime/stop, and idempotent thread/delete.
- thread/start creates only an ephemeral in-memory synthetic voice thread. It
  never loads history, configuration for coding work, skills, tools, MCP,
  approvals, rollouts, or a workspace session.
- Emit the compatible lifecycle, SDP, transcript, handoff-request, error, and
  closed notifications required by AgentVoice. Microphone and speaker media
  travel by WebRTC; stdio carries lifecycle, SDP, transcripts, delegations,
  and Fx speech results. Audio and text append methods unused by the accepted
  V3 path are not part of this product.
- Retain only V3 WebRTC call creation, AVAS sideband connection and bounded
  reconnection, transcript and delegation parsing, active-transcript tracking,
  speakable session-context append, and deterministic shutdown and transport
  errors. Omit V1, V2, websocket media, Responses API integration, and internal
  coding-turn routing.
- Client-managed delegation is intrinsic. Raw handoff requests remain visible,
  but no switch can enable automatic Codex delegation or transcript-tail
  routing.
- The accepted session identity is voice protocol V3,
  gpt-live-1-codex, voice cove, client delegation enabled, and acknowledgement
  filler disabled. The public compatibility request rejects a caller-supplied
  model; the sidecar itself sends the private V3 model `gpt-live-1-codex` in
  the AVAS session body, matching the reference implementation.
- Wrong session identifiers, speech before start, speech after stop, duplicate
  starts, and malformed sideband events fail clearly and do not create work.
  Reconnection never duplicates a handoff. Requested shutdown emits exactly
  one closed event with reason requested.
- The permanent gate records the first slim release binary size and dependency
  count as budgets. Later growth above either budget is a product decision,
  never an unnoticed consequence of upstream.
- Retires only if upstream ships a standalone boundary satisfying this entire
  runtime and dependency contract.

### Fx-owned authorization

- carry/fx-authorization, based on carry/voice-sidecar.
- Its external product dependency, Fx carry carry/codex-credential-authority,
  shipped in Fx Integration aa3c7c55. `--codex-credential-fd` is a global Fx
  flag, so it precedes the subcommand: `fx --codex-credential-fd 3 acp …`.
  Parsing an Fx session file is never an interim implementation.
- Fx is the sole authority for the configured Codex provider. One Fx login or
  configured provider supports both the orchestrator agent and realtime voice.
- Fx exposes the broker on interactive, resume, and ACP launches, all-or-none.
  Its directory is mode 0700, its socket mode 0600, and teardown
  removes only the socket owned by that Fx instance. AgentVoice obtains an
  already connected private descriptor from Fx and passes only that inherited
  descriptor to the sidecar; no capability appears in argv, environment,
  generic JSON-RPC, or a credential file. Broker admission binds the expected
  UID/PID, a one-time instance/session nonce, account, and generation. The
  broker remains separate from ADE telemetry and semantic work control.
- The broker is one persistent sequential schema-1 channel on the inherited
  descriptor: length-prefixed frames of at most 64 KiB, one request in flight,
  every response correlated to its request, and a per-frame deadline so a
  stalled partial frame fails rather than waits. codex.credential.resolve takes
  a minimum validity; codex.credential.refresh takes the pinned account ID and
  prior lease generation. A successful result contains only an access token,
  account ID, refresh deadline, and process-local generation — no plan
  metadata, and never a refresh token, serialized session, or store
  representation.
- The sidecar transport depends from its first commit on a narrow asynchronous
  VoiceAuthority-to-RuntimeLease interface. The initial parity carry adapts
  current Codex subscription auth; this follow-up replaces that adapter with a
  direct FxLeaseAuthority implementation and removes codex-login entirely.
- The sidecar does not invoke interactive login, read CODEX_HOME or auth.json,
  access a credential keyring, accept ambient OPENAI_API_KEY, refresh an
  access token itself, rotate or store a refresh token, or persist authority
  after exit.
- Fx owns refresh, rotation, provider selection, account identity, and
  persistence. A voice-session renewal obtains a new lease from Fx rather than
  teaching the sidecar credential ownership.
- Under `FX_AUTH_MODE=host-managed` Fx holds no provider credentials, so the
  broker has nothing to lease and fails closed, exactly as it does for borrowed
  read-only credentials.
- Fx pins the first accepted account. Every later load, OAuth result,
  persistence operation, and broker response must match it. Refresh is
  serialized: the current generation rotates once, an older generation
  receives the already newer lease, and a future generation fails.
- The sidecar also pins the first account before installing process-local
  tokens. It rejects an account change before creating headers or updating its
  in-memory authentication state.
- WebRTC call creation is auth-aware: create with the current lease; on the
  first 401 only, request external refresh, validate the account, rebuild the
  request and headers, and retry exactly once. A second failure is surfaced
  without a refresh loop. Proactive resolve remains required for expiry.
- Secrets never appear in argv, environment, logs, telemetry, crash output,
  artifacts, Git, or the Workshop scratchpad. They do not traverse
  AgentVoice's generic journaled JSON-RPC wrapper, and unrelated descendants
  inherit neither the connected descriptor nor token material.
- The sidecar fails closed when the lease is missing, expired, for a different
  provider or account, or cannot be renewed. Broker requests and its admission
  capability are process/session-bound, but the upstream access token is a
  bearer token and remains replayable if exfiltrated; the design prevents that
  exfiltration rather than claiming unavailable proof-of-possession. It never
  falls back to a second credential source.
- Broker tests cover normal resolve, near-expiry refresh, forced refresh,
  rotated-session persistence, stale and future generations, CAS conflicts,
  cancellation, timeout, account swaps, missing sessions, bounded framing,
  socket permissions, capability refusal, owned cleanup, recursive redaction,
  and descendant-environment stripping.
- Codpiece tests run with empty isolated HOME and CODEX_HOME and credential
  store, keyring, API-key, and login paths absent or configured to panic if
  touched. A 401-then-success test proves exactly one broker refresh, rebuilt
  headers, and changed-account rejection.
- AgentVoice evidence must prove one Fx-owned provider identity, no sidecar
  credential-store access, successful forced voice renewal with one Fx session
  rotation, continued Fx work after renewal, and no credential-bearing files
  or logs.
- Retires only if Fx no longer owns orchestration or upstream supplies an
  equally narrow external runtime-authority interface that Fx can drive without
  duplicate login.

## Gate

Run the Workshop scaffold validation first:

~~~sh
~/code/codpiece/tests/validate.sh
~~~

From the clean exact candidate worktree, run the constrained local build gate:

~~~sh
~/code/codpiece/scripts/gate.sh --worktree "$PWD"
~~~

The local gate runs `just test -p codex-voice-sidecar`, then
`just fix -p codex-voice-sidecar`, then `just fmt` without rerunning tests. It
fails if either mutating command changes the committed candidate. It must:

- run only tests for codex-voice-sidecar and its narrow transport modules;
- build only codex-voice-sidecar in release mode;
- use at most two Cargo jobs, disable release LTO, use one release codegen
  unit, strip packaged release symbols, and keep target data under
  /Volumes/Scratch when available;
- enforce the reviewed first-party dependency allowlist, reject forbidden
  dependency graphs and runtime notifications, and bind the full dependency
  graph hash;
- exercise mocked call creation, SDP, sideband parsing and reconnect,
  synthetic-thread state errors, speech append, and requested shutdown;
- run the fresh binary and enforce the version-controlled size and dependency
  budgets. The first slim build may only produce a measurement receipt; update
  the budgets in a paired Workshop commit and rerun before any live gate;
- leave no server, worker, child process, or worktree behind.

The local receipt names the exact fresh binary, its adjacent schema-3
metadata, and the candidate commit and tree. That receipt is the whole of the
build authority; the evaluation harness that once produced a second and third
receipt no longer exists, and nothing replaced it.

Proof that the product works is a person using it. AgentVoice ships
`bun run check`, which starts the real backend and sidecar, connects the
WebRTC peer, and makes the voice agent speak through the handoff path without
opening an audio device, and `bun run tui`, which is the thing itself. Run the
check after building a candidate; run the TUI before trusting one.

Whatever the surface, the invariant is unchanged.
A session must show zero Codex work turns: the sidecar delegates everything
and starts no coding turn of its own.

When Fx-owned authorization is exercised, the same session must show that Fx
was the only provider authority and that the sidecar touched no credential
store.

No hosted CI proof is required. The targeted local gate and a live session
are the blocking authorities, because the private realtime backend and the
full-duplex audio path cannot be proved by upstream CI.

Never run the full Codex test suite or a parallel release build as part of
this gate.

## Consumer

AgentVoice consumes an exact published Integration binary:

~~~sh
~/code/codpiece/scripts/install.sh --install --sha "$integration_sha"
~~~

The installer verifies the private mode-0600 local-build receipt under the
current gate contract, and the sidecar metadata bound to it. It rereads the
fork remote and published Integration SHA, builds that exact commit detached
in a SHA-isolated target under the Gate resource limits, and requires
byte-for-byte equality with the gated binary. That detached rebuild is the
reproducibility proof in the consumer path: if it does not match, the install
fails closed after publication and before pointer activation. It removes its
build worktree before activation, rereads the remote immediately before
atomically moving the sole consumer symlink to an immutable SHA directory, and
rolls that pointer back if post-activation verification fails. The immutable
install receipt names the immutable binary path, its metadata hash, and the
build receipt it came from; an existing immutable directory is accepted only
when its metadata bytes and private receipt still match. It never rebases,
publishes, chooses features, changes the official Codex CLI, or imports
credentials.

`CODPIECE_TESTING=1` is only for local filesystem fixtures. In test mode,
scripts that would otherwise skip canonical GitHub remote checks must reject
GitHub, SSH, and other non-file remotes before any fetch, push, or install
operation.

The sole moving pointer is `~/.local/lib/codpiece/current`; the stable binary
link resolves through it, and AgentVoice reads
`~/.local/lib/codpiece/current/install.json` rather than a moving branch or
ambient binary.

Any persistent fleet installer or launcher that begins invoking codpiece must
call this Workshop consumer and update the maintained fleet dependency map in
the same change. No downstream project may grow its own fork reconciliation.

## Notify

- Title: Codpiece Maintenance
- Group: codpiece.maintain
