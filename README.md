# DeepSeek 2.6.2 — optional API chat

This integration retains the supplied original application's sign-in, account footer,
account management and settings. It adds an **API Settings** row inside the original Settings list, using the original
settings cell class and typography. API mode is **off by default**; original login and chat continue using
the original service. Enabling API chat requires saving the configuration and restarting
the app. The existing sign-in flow is retained in both modes.

API settings support HTTPS Base URL, API Key, model, optional reasoning model, system
prompt, timeout, token-usage requests and a usage dashboard. API keys use the device-only
Keychain. API replies are stored locally. Signed-in account history is read from the original
service and cached with account isolation; it can be continued through API. API replies
are not uploaded to the original cloud.
Switching back to original mode also requires restarting.

The current replacement under development also adds an explicitly local Guest profile with a sign-in/API
prompt (it does not authenticate an official account), an optional conversation-list API entry, provider presets without keys, automatic
model discovery plus manual model names, and provider-specific reasoning effort.

API mode intercepts chat, chat sessions, file uploads and the corresponding guest challenge routes. Login,
account operations, original settings and bootstrap requests pass through to the original
service. Original mode keeps the original URLSession configuration and proof-of-work
implementation. No account modules, footer rows, settings rows or existing navigation
items are removed. The original data-management, agreement, help, logout and update
entries remain unchanged; API usage is inside the added API page.

This is an unsigned **test IPA**, not a claim of 100% UI/feature equivalence or physical
iPhone acceptance. API mode does not fully implement attachments, original search,
cloud sharing, voice input, automatic reading or widgets. Manual API-message reading
uses Apple voices; native start/stop and voice-preview regression has passed in the simulator. Those limitations
apply to API mode; original mode routes to the original services.

**Candidate 35 is withdrawn from acceptance:** service switching and unauthenticated image uploads were reported. A replacement is under native image and full regression testing; no new candidate is accepted for delivery yet.

See [ACCEPTANCE.md](ACCEPTANCE.md) for test scope. The repository contains adapter source,
not the supplied original app or credentials. GitHub Actions compiles an arm64 library
and repackages an exact-hash encrypted input while checking original resource preservation.
