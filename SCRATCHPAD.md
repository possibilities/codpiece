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

- carry/voice-sidecar: current-Main implementation retained at 245e64a081,
  including session- and delegation-context appends, the complete advertised
  V3 voice set, and corrected delegation-item test provenance; not yet
  published.
- carry/fx-authorization: recomposed above the current voice carry at
  76dbcecdb7, including the hello nonce handshake and exact request/response
  wire contract; not yet published.

## Current notes

- First bootstrap must explicitly create the active carries and Integration
  before the normal shared namespace reconciliation can run.
- AgentVoice currently has an operator-directed repo-local fallback that builds
  carry/fx-authorization when no Workshop installation exists. Explicit binary
  selection and `~/.local/lib/codpiece/current/install.json` take precedence.
  This conflicts with the permanent Integration-only consumer contract and is
  pending an explicit operator decision: either bootstrap and publish
  Integration so AgentVoice can delete the fallback and call this Workshop's
  installer, or revise the consumer ownership contract in a paired change.
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
- The reference oracle uses voice protocol V3, gpt-live-1-codex, intrinsic
  client delegation, and acknowledgement filler disabled. It was captured with
  voice cove; the product accepts all nine voices it advertises for V3.
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
- The current-Main, Fx-authorized delegation-context composition at
  56d4898991c6dc8fc6830b12d70a95f5a96eaf0f measures 3,634,320 binary
  bytes and 127 unique normal/build packages. Those exact values are the
  reviewed then-current budgets; the feature added no dependency declarations.
- That exact composition passed the constrained local gate. Its private
  schema-1 receipt is
  ~/.local/state/codpiece/local-builds/56d4898991c6dc8fc6830b12d70a95f5a96eaf0f.json;
  it remains unpublished and uninstalled.
- The complete Fx broker schema-1 wire correction at
  ac90b0fb3c02aceec27c0749405a71127096710a measures 3,651,376 binary bytes
  and 127 unique normal/build packages. The reviewed 17,056-byte growth adds
  the hello/nonce state, exact Fx field shapes, checked deadline conversion,
  bounded partial-frame handling, and terminal unauthorized behavior without
  adding a dependency.
- That exact candidate passed the constrained local gate. Its private
  schema-1 receipt is
  ~/.local/state/codpiece/local-builds/ac90b0fb3c02aceec27c0749405a71127096710a.json;
  it remains unpublished and uninstalled.
- AgentVoice's full-stack check passed against that unchanged candidate and Fx
  aa3c7c55: the schema-1 lease resolved, WebRTC connected, four downlink RTP
  packets decoded, and 3.6 seconds of audible model speech reached the
  harness. AgentVoice first corrected its conduit to create nonblocking
  socketpair endpoints as bare descriptors; its previous paused Node socket
  had prefetched the 85-byte hello frame and violated the opaque-transfer
  contract.
- The advertised-V3-voice composition at
  e226bd080bcf936c4aa2b2090bec00ad7e82d33d measures 3,651,392 binary bytes
  and 127 unique normal/build packages. The reviewed 16-byte growth makes the
  V3 start validator consume the same nine-voice V1 list returned by
  thread/realtime/listVoices; no dependency changed.
- That exact composition passed the constrained local gate. Its private
  schema-1 receipt is
  ~/.local/state/codpiece/local-builds/e226bd080bcf936c4aa2b2090bec00ad7e82d33d.json;
  it remains unpublished and uninstalled.
- AgentVoice reproduced that binary byte-for-byte and its full-stack check
  passed with non-default V3 voice juniper: Fx authorization resolved, WebRTC
  connected, four downlink RTP packets decoded, and 3.5 seconds of audible
  model speech reached the harness. The same check still passed with cove.
- A real delegation run against e226bd080b proved that AVAS indexes delegation
  context by the realtime item ID surfaced as `item_id`, not AgentVoice's
  distinct synthetic `handoff_id`. The sidecar already passed its API field
  through unchanged; the carry's misleading `handoff-42` test fixtures and the
  Workshop contract were corrected to name `item_id` explicitly.
- The corrected test-only composition at
  76dbcecdb7a6290e775237f3b837abd6f4cad938 retains the 3,651,392-byte and 127
  package budgets and passed the constrained 74-test local gate. Its private
  schema-1 receipt is
  ~/.local/state/codpiece/local-builds/76dbcecdb7a6290e775237f3b837abd6f4cad938.json;
  it remains unpublished and uninstalled.

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
- 2026-09-04: Rebased both active carries onto current Main, added Codex-parity
  channel selection and delegation-context append, and reviewed the first
  complete active-carry size and dependency budgets.
- 2026-09-04: Matched Fx's shipped credential-broker schema-1 handshake,
  request fields, response units, framing limits, and terminal refusal
  semantics after the first live schema-3 AgentVoice run exposed the mismatch.
- 2026-09-04: Replaced the historical cove-only start pin with validation
  against the full voice set advertised for V3, while retaining the fixed model
  and all other accepted session constraints.
- 2026-09-04: Corrected the delegation-context contract and carry test fixtures
  to identify AVAS's realtime item ID as `delegation_item_id`, distinct from
  AgentVoice's synthetic handoff ID.
