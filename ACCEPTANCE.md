# Optional API mode — acceptance status

Original login, account footer and every original settings entry are retained. API chat is optional and off by default. Save a mode change and restart before sending.

## Component and provider checks

Candidate 43, source `dcd628d858059dfb2f9b705e5733e36566c71b63`, passes the six component suites: streaming/configuration, local history, attachments, protocol routing, actual Foundation upload-task variants, and the OpenAI-compatible client. ARM64 compilation, package/resource preservation and ZIP integrity pass. These checks do not establish native attachment acceptance.

The official DeepSeek API passed six production-client cases (Unicode, thinking, context, cancellation, wrong key and wrong model), and separate synthetic-image HTTP/SSE tests. No user screenshot was submitted. Live-provider tests of the complete IPA image flow have not passed.

## Native simulator results

Candidate 42 full native suite, probe 41: six of seven cases passed. Native streaming, cancellation, regeneration, manual reading start/stop, four repeated original/API mode changes, and settings passed. Settings coverage includes retained account/data/legal/help/logout entries, voice selection and CAF preview, font size, personalization, language restart, API configuration and usage controls. Language restart uses a disposable locale override; actual selection in iOS Settings is not proven.

The image test failed: multipart bytes were retained, but the original file model reported `UPLOAD_FAILED (LOCAL_UNEXPECTED)` and no image reached the provider. Candidate 43 changes the upload response envelope; native image validation is pending. Candidate 35 is superseded and is not accepted.

## Remaining limits

No physical iPhone, self-sign/install, genuine account login, device Keychain or switching with real cloud history has been tested. Simulator bootstrap uses a separate disposable fixture, never included in the delivered adapter.

API history is local and separate from cloud history. Original web search, cloud sharing, voice input, automatic reading and widgets are not fully adapted in API mode. Manual API reading uses Apple voices. Original-service mode retains its original backend behavior. Complete original UI/function equivalence is not established.

No replacement IPA is accepted for delivery while native image regression fails.
