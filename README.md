# DeepSeek API adapter — work in progress

Native iOS adapter modules under development for a user-supplied DeepSeek 2.6.2 application.

**Experimental integration candidate, not a verified replacement application.**
The modules now include runtime routing for the user-supplied 2.6.2 binary.
Compilation and component tests do not establish that the original app starts
or that its UI and all features behave correctly on an iPhone.

An [experimental unsigned IPA](https://github.com/JLjingluo/deepseek-api-adapter-20261016/releases/tag/experimental-ipa-2.6.2)
is now available for self-signing. It is **not a completed or verified 100% equivalent app**.
Its accompanying manifest records CRC validation, 734 unchanged original archive
entries and 29 unchanged original TEXT sections. These checks do not establish
startup or functional correctness. The known feature gaps below still apply.

Current modules:

- HTTPS Base URL, API key, primary/reasoning model, system prompt and timeout configuration.
- Device-only Keychain storage for the API key.
- Native settings controller and an experimental original-settings entry hook.
- Streaming OpenAI-compatible HTTP client and incremental SSE parser.
- Local conversation persistence, message branches, titles, pinning and deletion.
- Experimental conversion of API text/reasoning deltas into the original message events.
- Runtime validation of local identity data using the original app's decoder.
- GitHub Actions compilation on macOS and tests of fragmentation and completion errors.

The source tree contains no original IPA, application resources, credentials or
original source code. The GitHub workflow compiles the adapter and packages an
experimental unsigned IPA from the exact encrypted input, with resource checks.
The integration preserves the original binary's UI implementation and resources;
it has not been visually compared on a device. It reroutes account-dependent
startup through a local context. Original compiled account/login code remains in
the supplied application: this is **not** physical removal of those modules.

OpenAI-compatible text chat alone does not supply the original app's search,
cloud sharing, voice calls or attachment services. Those capabilities need separate
compatible services before equivalent behavior can be claimed. Unsupported routes
fail explicitly instead of falling back to the original conversation service.

Limitations: original-app startup, runtime type lookup, event conversion, settings
hooks, background behavior, original widgets and actual API requests have not been
verified on an iPhone. These must not be described as passed tests.

An additional manually dispatched `simulator-probe.yml` workflow investigates
whether a disposable copy of the original arm64 binary can run on an ARM iOS
simulator after platform metadata conversion. Its encrypted input key is an
Actions secret; raw application input is not part of the source tree or diagnostic
archive. This experiment does not change the device delivery input and is not
proof of physical-device compatibility or 100% feature/UI equivalence.
