# Maintenance scratchpad

This file is current state for the shared maintain skill. It records no green
baseline until the first voice-sidecar candidate has actually passed its gate.

## Delivered baseline

- No codpiece product has been delivered or installed yet.
- The accepted oracle is the AgentVoice Codex-Fx run built from Codex revision
  430d26b543b219049192de559987b8cf506efacf plus the client-managed handoff
  patch in ~/code/agentvoice.
- The product fork has not yet published Integration or the active voice carry.

## Audited-upstream frontier

- No complete maintenance audit has run.
- The Workshop was initialized and the bound checkout was fast-forwarded while
  openai/codex main was
  a9519cbcdd2d664530edb2469224ee03c1056799. This is orientation evidence, not
  an audited frontier.

## Carried state

- carry/voice-sidecar: required and not yet delivered.
- carry/fx-authorization: implementation retained at 1d9e28b607 in
  ~/src/codex-codpiece-fx-authorization-20260831; not yet gated or published.

## Current notes

- First bootstrap must explicitly create the active carries and Integration
  before the normal shared namespace reconciliation can run.
- The paired Fx dependency shipped: carry/codex-credential-authority is in Fx
  Integration aa3c7c55, and --codex-credential-fd is a global flag that
  precedes the subcommand.
- The fork Main observed at bootstrap is
  d109393270432531ac0010542ae7973801e0d9d7 and must be advanced atomically
  with the first declared namespace publication.
- Final single-authority delivery also requires a new Fx carry,
  carry/codex-credential-authority. Current Fx keeps its provider session
  opaque and has no safe runtime lease endpoint. Codpiece's paired planned
  follow-up is carry/fx-authorization; neither becomes active before voice
  parity.
- The reference oracle uses voice protocol V3, gpt-live-1-codex, voice cove,
  intrinsic client delegation, and acknowledgement filler disabled.
- Constrained Rust builds are mandatory: at most two Cargo jobs, release LTO
  disabled, one release codegen unit, stripped packaged symbols, and
  Scratch-backed target data.
- The first stripped slim-build measurement at
  eda09b44e2a87ad0dfaa9e03a0e05787616856ad is 3,563,472 binary bytes and
  129 unique normal/build packages. Those exact values are the initial
  zero-slack growth budgets.
- Production selected-workspace support at
  fe3bad9abfe0be8e662604694dfc99536a70dbb3 adds 16 binary bytes, for a
  reviewed 3,563,488-byte budget; the dependency budget remains 129.

## History

- 2026-08-30: Workshop repository initialized. No maintenance cycle or product
  publication has yet occurred.
- 2026-08-31: Established the first stripped voice-sidecar size and dependency
  budgets from the constrained local measurement gate.
- 2026-08-31: Expanded the binary budget by 16 bytes for validated ChatGPT
  selected-workspace authorization; package count did not change.
- 2026-09-03: Retired the artifact and ship gates with the AgentVoice
  evaluation harness they depended on. The local build receipt is now the only
  build authority, the gate emits schema-3 metadata with the credential
  authority block, and the product is proved by a person using AgentVoice's
  check and TUI. Activated carry/fx-authorization in the inventory.
