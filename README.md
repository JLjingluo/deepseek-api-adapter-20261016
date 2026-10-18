# DeepSeek 2.6.2 — optional API chat

This integration retains the supplied original application's sign-in, account footer,
account management and settings. It adds an **API** button to the original Settings
navigation bar. API mode is **off by default**; original login and chat continue using
the original service. Enabling API chat requires saving the configuration and restarting
the app. The existing sign-in flow is retained in both modes.

API settings support HTTPS Base URL, API Key, model, optional reasoning model, system
prompt, timeout, token-usage requests and a usage dashboard. API keys use the device-only
Keychain. API conversations are local and separate from original cloud conversations;
cloud conversations are not migrated to the API store. Start a new chat after switching.
Switching back to original mode also requires restarting.

In API mode only `/api/v0/chat/` and `/api/v0/chat_session/` are intercepted. Login,
account operations, original settings and bootstrap requests pass through to the original
service. Original mode keeps the original URLSession configuration and proof-of-work
implementation. No account modules, footer rows, settings rows or existing navigation
items are removed. The original data-management, agreement, help, logout and update
entries remain unchanged; API usage is inside the added API page.

This is an unsigned **test IPA**, not a claim of 100% UI/feature equivalence or physical
iPhone acceptance. API mode does not fully implement attachments, original search,
cloud sharing, voice input, automatic reading or widgets. Manual API-message reading
uses Apple voices and has not passed full active-state UI regression. Those limitations
apply to API mode; original mode routes to the original services.

[Download the full unsigned test IPA](https://github.com/JLjingluo/deepseek-api-adapter-20261016/releases/download/candidate-35/DeepSeek-API-2.6.2-experimental-unsigned.ipa).

See [ACCEPTANCE.md](ACCEPTANCE.md) for test scope. The repository contains adapter source,
not the supplied original app or credentials. GitHub Actions compiles an arm64 library
and repackages an exact-hash encrypted input while checking original resource preservation.
