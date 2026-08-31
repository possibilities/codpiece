# codpiece context

**Workshop** — This repository, which owns the voice-fork specification,
maintenance state, gate, and exact-SHA consumer handoff.
_Avoid_: patch repository, wrapper.

**Voice sidecar** — The standalone codex-voice-sidecar binary that owns one
realtime voice session and exposes the narrow compatibility protocol used by
AgentVoice. It has no coding-agent runtime.
_Avoid_: stripped App-server, backend agent, Codex orchestrator.

**Voice agent** — The realtime speech model that listens, speaks, manages
interruption, and delegates workspace work.
_Avoid_: speech wrapper, orchestrator.

**Orchestrator agent** — The persistent Fx coding agent that investigates,
edits, runs tools, and returns work results.
_Avoid_: backend agent, voice model.

**Synthetic voice thread** — The ephemeral in-memory identifier and lifecycle
state exposed for App-server protocol compatibility. It is never a Codex
coding thread and has no workspace state.
_Avoid_: Codex thread, fake coding session.

**Client-managed delegation** — A voice-model request surfaced to AgentVoice
for routing to Fx, with no internal Codex turn or transcript-tail routing.
_Avoid_: tool call, optional handoff mode.

**Fx authority** — The single configured Codex provider authority owned,
refreshed, and persisted by Fx for both orchestration and voice access.
_Avoid_: shared auth file, sidecar login.

**Credential broker** — The private Fx Unix-socket service that resolves or
refreshes a bounded access-token lease from Fx's opaque Codex session while
keeping refresh tokens and store representations inside Fx.
_Avoid_: auth proxy, AgentVoice RPC, credential file reader.

**Runtime authority lease** — A bounded, non-persisted capability delivered by
the Credential broker to one voice-sidecar process so it can establish or
renew its realtime session without owning credentials. It includes an access
token, pinned account identity, refresh deadline, and monotonic generation,
never a refresh token.
_Avoid_: copied auth.json, API key, refresh token handoff.

**Reference oracle** — The pinned full Codex App-server voice run and its
accepted compact full-duplex artifacts, used to prove behavioral parity.
_Avoid_: permanent sidecar, implementation base.

**Integration branch** — possibilities/codex:integration, the exact composition
of every current carried feature and the sole source the consumer builds.
_Avoid_: install latest, development main.

**Main mirror** — Local main and possibilities/codex:main at the exact current
openai/codex:main commit, with no downstream work.
_Avoid_: integration base with patches, fork main.

**Carry branch** — A durable carry/<feature> head containing one required
downstream behavior, based on Main or its declared carry dependency and
composed into Integration.
_Avoid_: temporary branch, pull-request branch.

**Maintenance cycle** — One maintain run that audits upstream, reconciles every
feature, gates and publishes an exact Integration commit, installs it, and
records the resulting state.
_Avoid_: update, rebuild.
