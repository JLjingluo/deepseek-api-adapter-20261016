# Acceptance evidence and remaining work

The project does not meet complete original-app parity yet. The latest full unsigned
package is [candidate-26](https://github.com/JLjingluo/deepseek-api-adapter-20261016/releases/tag/candidate-26).
The user must sign it before installation on a non-jailbroken iPhone.

## Verified evidence

| Check | Evidence | Scope |
| --- | --- | --- |
| Compilation, component checks, full IPA | Actions build 39096662400 | Candidate 26; arm64 device target |
| Original resources preserved | Package verification manifest | 734 archive entries and 29 TEXT sections unchanged |
| Original UI displays incremental replies | Simulator probes 20 and 22, testNativeApp passed | Source-built instrumented adapter, local HTTPS SSE fixture |
| Settings item identification | Probe 22 runtime report | Original Swift diffable items resolved; usage dashboard opened |
| Real official API client | live-client-results-2 | Production Objective-C client on macOS: Unicode, thinking, context/system, cancellation, invalid key/model; six cases passed |
| Actual usage aggregation | live-client-results-2 | 92 input + 27 output = 119 tokens across three reported successes |
| Native read-aloud message routing | Probe 20 runtime report | Original read button resolved message 2; speech completion callback observed; audible output not established |

## In progress

Probe 23 checks native cancellation, active read-aloud state, removed account/help/legal/logout
rows, font size, personalization, voice selection, language switching and API settings.
A failure or unvisited screen is not an accepted feature. Packaged-library runtime testing
and a physical iPhone remain required for broader acceptance.

The simulator runs the supplied original arm64 app with platform metadata converted in a
disposable copy. The device IPA keeps its device metadata. Simulator-only code supplies a
loopback HTTPS mock configuration when ad-hoc simulator signing rejects Keychain writes.
This fallback is not compiled into the delivered adapter and does not prove device Keychain
behavior. API keys in production use the device-only Keychain.

## Known gaps

Attachments, the original search backend, cloud sharing, voice input, widgets and automatic
read-aloud are not fully adapted. Manual reading currently uses installed Apple voices;
these are not the original DeepSeek cloud voices. Newly added settings support English,
Simplified Chinese and Traditional Chinese; other app languages currently use English for
new labels. Complete language parity and all original functions have not been established.

Login/account screens are bypassed and settings entries removed through runtime integration.
Original compiled login modules still exist in the supplied executable. Unknown backend
routes fail locally rather than silently connecting to the original chat service.

No user GitHub token, live API key or mock key is embedded in the delivered IPA.
