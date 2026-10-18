# DeepSeek 2.6.2 — optional API chat, test 1

This is a complete unsigned test IPA based on the supplied original application. Original login, account footer, settings and chat UI remain. A native **API Settings** row is added to the original account/settings group. A local Guest option skips login without authenticating an official account.

API settings support provider presets without keys, HTTPS Base URL, manually entered Keychain API Key, automatic `/models` discovery and manual models, optional thinking model, reasoning effort, system prompt, timeout and usage tracking. An optional setting shows an API shortcut in the conversation sidebar. A clean install defaults to original-service mode. Save and restart after changing modes.

With valid original-account login, API mode imports and caches cloud conversations with account isolation. Old conversations can be continued through API; refresh preserves those local turns. API-generated replies remain on the device and are **not uploaded to the official cloud**. An API key alone cannot retrieve account history.

The current package passed the nine-case native suite, the documented Guest restart/sign-in flow and a real official DeepSeek native-image request (HTTP 200). The six component suites include late identity loading, token rotation and cross-account rejection. Tests do not establish real-account or physical-iPhone acceptance. See [ACCEPTANCE.md](ACCEPTANCE.md) for exact scope and limitations.

API image and UTF-8 text attachments are supported; all original attachment types are not. Original search, cloud sharing, voice input, automatic reading and widgets are not fully adapted in API mode. Manual API reading uses Apple system voices. Original mode retains its original service routes. **100% UI/feature equivalence and a bug-free application are not claimed.**

The IPA requires your own signing. Do not uninstall or clear app data to troubleshoot synchronization: local API replies need a separate backup. The repository contains adapter source, not the original application's source or credentials. GitHub Actions builds arm64 and verifies preserved original resources/TEXT against the exact encrypted input.
