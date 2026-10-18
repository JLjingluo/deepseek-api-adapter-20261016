# Optional API mode — test acceptance

The latest user instruction changes the design: preserve original login and account UI,
and add optional API chat. Earlier candidates that removed account/settings entries
are superseded; their native UI results do not validate this design.

## Current checks

The four component suites include SSE/configuration, persistent local conversations,
native protocol routing and the production OpenAI-compatible client. New routing checks
run in separate processes with API mode off and on: login, account, settings and bootstrap
pass through in both modes; chat interception follows the startup mode; mode changes
remain deferred until relaunch. Other component cases cover byte fragmentation, reasoning,
history branches, regeneration including native child_message_id, HTTP errors, timeout,
cancellation, token usage on/off and absent usage without estimates.

Earlier official API live tests passed six production-client cases and nine HTTP-level
cases. These do not establish a real logged-in, end-to-end IPA conversation.

Candidate **35**, commit `c90ed1e2cc180398048edab92a1670bfcbed4709`,
[build 39115680984](https://github.com/JLjingluo/deepseek-api-adapter-20261016/actions/runs/39115680984):
all four suites, arm64 compile and full IPA packaging passed.

## Unverified and incomplete

Physical iPhone self-sign/install, actual login, account management after login, device
Keychain and switching modes with real cloud history have not been verified. No user
account credentials are used in CI. The new settings page has not completed native UI
regression. Complete original UI/function equivalence is not established.

API mode keeps local history separately and does not migrate cloud conversations.
Start a new API conversation after switching; existing cloud conversations can require
returning to original mode. Attachments, original web search, cloud sharing, voice input,
automatic reading and widgets are incomplete in API mode. Manual API-message reading
uses Apple voices; the previous full suite's active-state assertion failed, so that
feature is not accepted as fully verified. The original-service mode retains the original
speech behavior and all original backend routes.

ZIP integrity, package identity and credential scanning are recorded alongside the release.
Resource-preservation checks alone do not prove runtime/UI correctness.
