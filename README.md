# DeepSeek 2.6.2 — optional API chat, test 2

[Download the complete unsigned test IPA](https://github.com/JLjingluo/deepseek-api-adapter-20261016/releases/download/candidate-60/DeepSeek-API-2.6.2-Test2-unsigned.ipa). Sign it yourself; use the same bundle identifier and signing configuration when updating to preserve local conversations.

This build preserves the original login/account UI and adds optional OpenAI-compatible API settings, a local Guest entry and the approved sidebar shortcut. API mode defaults off on clean installations. Choose a provider, enter your own key, enable API, save, close the app and reopen it.

The build adds actionable errors for credential, HTTP, DNS, offline, TLS, timeout and stream failures, plus saved-connection testing and sanitized diagnostic copying inside API Settings. Keychain writes are checked by reading back the saved value; no keys or chat content are stored in diagnostics. Provider presets, model discovery/manual entry, optional thinking model/effort, timeout, system prompt and usage tracking remain available.

Exact packaged adapter acceptance: native suite 86 **10/10**, HTTP/clipboard UI probe 85 **passed**, real Keychain + restart + direct official API text/image probe 91 **passed**, official production-client suite 5 **8/8**. Probe 91 uses the real secure input and Security.framework methods with a locally signed simulator application, without credential replacement or API forwarding. All provider traffic in that probe targets api.deepseek.com.

Probe 89 passed secure storage, the required restart and the direct connection check, but timed out on an extra second cold launch; that probe is recorded as failed. Probe 90 also passed saved/restarted connectivity but failed to return from Settings because the automation used a stale navigation identifier. It is not counted as passed. Probe 91 follows the required save/restart flow and returns through the original settings close control for chat acceptance. No universal repeated-launch guarantee is inferred.

**The user's original physical-device failure has not been directly observed with their signing certificate and network.** Simulator passes do not establish physical-iPhone acceptance. If the device still fails, copy the detailed error or open API Settings → Latest request details. See [ACCEPTANCE.md](ACCEPTANCE.md) for exact scope and signing limitations.

The image API reply is verified, but its chat thumbnail is still gray in the captured screenshot; final thumbnail rendering is not accepted yet.

Original-account history requires valid original login. API continuation is local only and does not upload replies to the official cloud. Image/UTF-8 attachments and manual Apple-system-voice reading are supported; all original search, sharing, voice input, automatic reading, widgets and attachment formats are not fully adapted. Full UI/feature equivalence and a bug-free application are not claimed.

IPA SHA-256: `20b1fe212f914f9068b6c9267f0296db399a353dde87bc591d27efc61617579d`. No provided credentials or test observers are bundled.
