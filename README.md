# DeepSeek 2.6.2 — optional API chat, Test 2.1

[Download the complete unsigned IPA](https://github.com/JLjingluo/deepseek-api-adapter-20261016/releases/download/candidate-62/DeepSeek-API-2.6.2-Test2.1-unsigned.ipa). Sign it yourself. Preserve the bundle identifier and signing configuration when upgrading to keep local data.

Preserves the original login/account UI and adds optional OpenAI-compatible API settings in the native settings list, Guest entry and the approved sidebar shortcut. API mode defaults off on clean installations. Choose a provider, enter your own key, enable API, save and fully reopen the application.

Includes actionable API errors, verified Keychain writes, saved-connection testing and sanitized diagnostic copying. Fixes native thumbnails for local API image attachments without changing the image UI or intercepting original CDN files.

Exact-package acceptance: **10 native regression scenarios**, nine passed in run 93 and cancellation revalidated in focused run 97 after correcting the test's placeholder-based composer lookup, native HTTP/copy probe 96 **passed**, real Keychain/save/restart/direct official text and image probe 95 **passed**. Both image runs require actual red thumbnail pixels in screenshots. Production client suite 5 passed **8/8**; its client/config/SSE sources are unchanged. All component suites and package integrity checks passed.

Physical iPhone installation with the user's signing certificate/network remains unverified. A prior extra simulator cold launch timed out; arbitrary repeated-launch stability is not claimed. See [ACCEPTANCE.md](ACCEPTANCE.md) for evidence and limits.

Original history needs valid original login; API replies stay local. Image/UTF-8 attachments and manual system TTS are supported. All original search, sharing, voice input, automatic reading, widgets and attachment formats are not fully adapted. Full original feature/UI equivalence and a bug-free application are not claimed.

SHA-256: `8f34202fc1f57f704300f229d4a38afb2a51915c333413018cbfb8ea0d2b37b6`. No supplied credentials or test observer is bundled.
