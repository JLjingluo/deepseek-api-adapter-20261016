# DeepSeek API adapter — work in progress

Native iOS adapter modules under development for a user-supplied DeepSeek 2.6.2 application.

**This repository does not currently produce a working modified IPA.** The
original application's service boundaries and local account/session context must
still be integrated and tested. A compiled library alone does not complete that work.

Current modules:

- HTTPS Base URL, API key, primary/reasoning model, system prompt and timeout configuration.
- Device-only Keychain storage for the API key.
- Native settings controller, awaiting insertion into the original settings page.
- Streaming OpenAI-compatible HTTP client and incremental SSE parser.
- GitHub Actions compilation on macOS and tests of fragmentation and completion errors.

The project contains no original IPA, application resources, credentials or
original source code. The GitHub workflow builds only the adapter library.
No original UI has been replaced. Original-app integration is not yet implemented.

OpenAI-compatible text chat alone does not supply the original app's search,
cloud sharing, voice calls or attachment services. Those capabilities need separate
compatible services before equivalent behavior can be claimed.
