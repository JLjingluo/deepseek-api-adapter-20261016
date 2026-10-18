# Optional API mode — acceptance status

Original login, account footer and original settings entries are retained. API chat is optional and off by default. Save a mode change and restart before sending.

## Component and official-provider checks

Candidate 48, source `2a2f7a29d5a1c2cf0bad3a02a5cd475dbffe5962`, passes six component suites: streaming/configuration, local history, attachments, protocol routing, real Foundation upload-task variants, and the OpenAI-compatible client. The protocol suite also verifies API-disabled local Guest blocking. ARM64 compilation, original resource/TEXT preservation, ZIP integrity and a scan for real credentials/test keys pass.

Official DeepSeek production-client tests passed eight cases: Unicode, thinking, conversation context, cancellation, wrong key, wrong model, Max reasoning and model discovery. These eight requests reported 177 tokens in total.

Packaged candidate 48 passed native live-image probe 51. A synthetic red square was attached through the original UI, uploaded through the adapter, sent to official DeepSeek (`deepseek-chat`, HTTP 200), and the expected reply was rendered. Reported usage was 1,015 tokens. No user screenshot was submitted. The decode failure was caused by a JSON number in a strict Boolean field; `is_image` now serializes as a Boolean. The temporary provider CI secret was removed after the test.

## Native simulator checks

Earlier candidate 45 full native probe 43 passed native streaming, cancellation, regeneration, manual reading, repeated original/API mode changes and original/API settings. The original-account cloud-history fixture appeared in the native sidebar; continuation still required a test input-selector correction. Candidate 48 re-runs the complete suite, including model discovery/presets/reasoning and cloud-history continuation. Final results are pending.

Settings checks include retained account/data/legal/help/logout entries, voice selection and CAF preview, font size, personalization, language restart, API configuration and usage controls. Language restart uses a disposable locale override; actual selection inside iOS Settings is not proven.

Candidate 48 Guest probes 49/50 failed before entering the conversation UI. Candidate 49 brings the Skip control above the original welcome content and adds action diagnostics. Guest startup with API enabled/disabled, API activation/restart, and returning to original login require native acceptance.

## History behavior and limits

With an existing valid original-account login, API mode reads cloud conversation pages and messages through the original authenticated routes, caches them per account, and permits local API continuation. Refresh preserves local API branches. API-generated messages are not uploaded to the original cloud. An API key alone cannot access official-account history. Offline fallback uses previously cached history and reports synchronization errors. Cloud file references not present in the local attachment store remain a limitation.

No physical iPhone, self-sign/install, genuine account login, device Keychain or real-account cloud history has been tested. Simulator account/backend fixtures are separate diagnostics and are not included in the delivered adapter. Original web search, cloud sharing, voice input, automatic reading and widgets are not fully adapted in API mode. Manual API reading uses Apple voices. Complete original UI/function equivalence is not established.

No new replacement IPA is accepted for delivery until the pending native regressions are resolved.
