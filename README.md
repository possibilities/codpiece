# codpiece

Codpiece is the Workshop for maintaining the smallest useful piece of Codex:
a standalone voice-only sidecar for AgentVoice.

The product fork remains possibilities/codex. Its main branch mirrors
openai/codex, its durable carried behavior lives under carry/, and its
integration branch is the only consumer source. This repository owns the
contract, gate, exact-SHA installer, and maintenance state.

The target architecture is:

~~~text
microphone and speaker
        ⇅ WebRTC
codex-voice-sidecar
        ⇅ client-managed delegations and speech handoffs
AgentVoice
        ⇅
Fx orchestrator and Fx-owned Codex authority
~~~

The accepted full Codex App-server demo in ~/code/agentvoice is the oracle.
Codpiece replaces only its voice transport and compatibility surface; Fx
continues to perform every workspace turn.

Delivery is deliberately phased: first reproduce that oracle with the tiny
voice sidecar and current Codex subscription authority, then add the paired Fx
credential broker and remove the sidecar's independent Codex authorization.

Validate the Workshop with:

~~~sh
tests/validate.sh
~~~

After a maintenance cycle publishes an exact Integration SHA, install it with:

~~~sh
scripts/install.sh --install --sha FULL_40_CHARACTER_SHA
~~~
