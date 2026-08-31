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

## Current notes

- First bootstrap must explicitly create the active voice carry and Integration
  before the normal shared namespace reconciliation can run. The authorization
  carry is added only after voice parity.
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

## History

- 2026-08-30: Workshop repository initialized. No maintenance cycle or product
  publication has yet occurred.
