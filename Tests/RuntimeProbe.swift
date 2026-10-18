// Simulator investigation only. Never included by the delivery module build.
import Foundation
import UIKit

@_cdecl("DSAPIRunRuntimeProbe")
public func runRuntimeProbe() {
    let session: [String: Any] = ["id": "probe-session", "title": "新对话", "title_type": "SYSTEM",
        "pinned": false, "updated_at": 1_760_000_000, "inserted_at": 1_760_000_000,
        "is_empty": false, "model_type": "default", "version": 1, "current_message_id": 2]
    let message: [String: Any] = ["message_id": 2, "parent_id": 1, "role": "ASSISTANT",
        "fragments": [["id": 2, "type": "RESPONSE", "content": "流式输出测试", "references": [], "stage_id": 0]],
        "status": "FINISHED", "quasi_status": "FINISHED", "thinking_enabled": false,
        "ban_edit": false, "ban_regenerate": false, "tips": [], "conversation_mode": "CHAT",
        "search_enabled": false, "search_triggered": false, "extra_search_providers": []]
    let file: [String:Any] = ["id":"api-file-probe","file_name":"red.png","file_size":75,"inserted_at":1_760_000_000,"updated_at":1_760_000_000,"from_share":false,"status":"SUCCESS","token_usage":0,"is_image":true,"audit_result":"pass","width":8,"height":8,"signed_path":"https://chat.deepseek.com/api/v0/file/local/api-file-probe"]
    let fixtures: [(String, Any)] = [
        ("ServerModels.File",file),
        ("ServerModels.Response.FetchFile",["files":[file]]),
        ("ServerModels.Message.FileFragment",["id":3,"type":"FILE","files":[file]]),
        ("ServerModels.Response.TTSVoiceConfig", ["voices": [["voice_id": "local-voice", "name_i18n": ["en": "Local voice"],
            "description_i18n": ["en": "Device speech"], "languages": ["en-US"], "demo_urls": ["en": "https://chat.deepseek.com/api/v0/chat/tts/local_demo/local-voice"],
            "is_default": true, "color_palette": ["c1": "#496BFF", "c2": "#95ACFF", "c3": "#E5EAFF"]]],
            "default_voice_id": "local-voice", "current_voice_id": "local-voice"]),
        ("AppModels.User", ["id": "local-api", "token": "local-api-no-official-account", "email": "",
            "mobile": "", "idProfiles": [], "chat": ["isMuted": 0], "needBirthday": false]),
        ("ServerModels.Session", session), ("ServerModels.Message", message),
        ("ServerModels.Completion.ReadyChunk", ["request_message_id": 1, "response_message_id": 2,
            "model_type": "default", "request_content": "测试", "ban_edit": false]),
        ("ServerModels.Completion.TitleChunk", ["content": "新对话"]),
        ("ServerModels.Completion.FinishChunk", [String: Any]()),
        ("ServerModels.POV", ["p": "response", "o": "SET", "v": message]),
        ("ServerModels.Response.ClientSettings", ["version": 0, "settings": [:]]),
        ("ServerModels.Response.Challenge", ["algorithm": "SHA-256", "challenge": String(repeating: "0", count: 64),
            "salt": "local-api-handshake", "signature": "local-only", "difficulty": 0,
            "expire_at": 1_900_000_000_000, "expire_after": 3_600_000]),
        ("ServerModels.Response.ChatSessionFetchPage", ["chat_sessions": [session], "has_more": false]),
        ("ServerModels.Response.ChatHistoryMessages", ["chat_session": session, "chat_messages": [message],
            "cache_control": "REPLACE", "cache_reset_at": 0])
    ]
    var results: [[String: Any]] = []
    for (name, value) in fixtures {
        var result: [String: Any] = ["type": name]
        // These fixture names have enum namespaces and a struct leaf, as
        // observed in this input's nominal type descriptors.
        let parts = name.split(separator: ".").map(String.init)
        let namespaces = parts.dropLast().map { "\($0.utf8.count)\($0)O" }.joined()
        let leaf = parts.last!
        let mangled = "13DeepSeek_Chat" + namespaces + "\(leaf.utf8.count)\(leaf)V"
        let resolved = _typeByName("DeepSeek_Chat." + name) ?? _typeByName(mangled)
        if let type = resolved as? any Decodable.Type {
            do {
                let decoded = try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
                result["decoded"] = true
                result["reflection"] = String(reflecting: decoded)
                if name == "ServerModels.Response.Challenge" || name == "ServerModels.Response.ChatHistoryMessages" {
                    result["known_enum_values"] = !String(reflecting: decoded).contains(".unknown")
                }
                if let encodable = decoded as? any Encodable,
                   let encoded = try? JSONEncoder().encode(encodable),
                   let canonical = try? JSONSerialization.jsonObject(with: encoded) {
                    result["canonical"] = canonical
                }
            } catch { result["decoded"] = false; result["error"] = String(describing: error) }
        } else { result["resolved"] = false }
        results.append(result)
    }
    var views: [[String: Any]] = []
    func visit(_ view: UIView, _ depth: Int) {
        guard views.count < 1500, depth < 40 else { return }
        var item: [String: Any] = ["class": NSStringFromClass(type(of: view)), "depth": depth,
            "hidden": view.isHidden, "frame": NSCoder.string(for: view.frame)]
        if let label = view as? UILabel { item["text"] = label.text ?? ""; item["font_point_size"] = label.font.pointSize }
        if NSStringFromClass(type(of: view)).hasSuffix(".FontSizeSlider") {
            // Test-only observation: expose the original handle position. Native
            // gestures still perform the change; no production control is replaced.
            view.isAccessibilityElement = true
            view.accessibilityIdentifier = "DSAPI.NativeFontSlider"
            if let handle = Mirror(reflecting: view).children.first(where: { $0.label == "handleView" })?.value as? UIView,
               view.bounds.width > 0 {
                view.accessibilityValue = String(format: "%.4f", handle.center.x / view.bounds.width)
                item["native_handle_position"] = handle.center.x / view.bounds.width
            }
        }
        if let button = view as? UIButton { item["title"] = button.title(for: .normal) ?? "" }
        if let table = view as? UITableView {
            item["delegate_class"] = table.delegate.map { NSStringFromClass(type(of: $0 as AnyObject)) } ?? "none"
            if let source = table.dataSource {
                item["data_source_class"] = NSStringFromClass(type(of: source as AnyObject))
                item["data_source_fields"] = Mirror(reflecting: source).children.map {
                    "\($0.label ?? "unnamed"): \(String(reflecting: type(of: $0.value)))"
                }
            }
        }
        if let cell = view as? UITableViewCell {
            item["corner_radius"] = cell.layer.cornerRadius
            item["masked_corners"] = cell.layer.maskedCorners.rawValue
            item["clips_to_bounds"] = cell.clipsToBounds
        }
        if NSStringFromClass(type(of: view)).hasSuffix(".UserMessageCell") {
            let mirror = Mirror(reflecting: view)
            if let model = mirror.children.first(where: { $0.label == "currentMessage" })?.value {
                let state = Mirror(reflecting: model).children.first(where: { $0.label == "clientStatus" })?.value
                if let state {
                    let value = String(reflecting: state)
                    item["native_client_status"] = value
                    UserDefaults.standard.set(value, forKey: "DSAPIAdapter.observedNativeClientStatus")
                }
            }
        }
        if NSStringFromClass(type(of:view)).contains("InputFileImageCell") {
            var mirror:Mirror?=Mirror(reflecting:view)
            while let level=mirror {
                if let file=level.children.first(where:{$0.label=="file"})?.value {
                    var model:Any=file
                    if Mirror(reflecting:model).displayStyle == .optional,let value=Mirror(reflecting:model).children.first?.value { model=value }
                    var state:[String:String]=[:]
                    for child in Mirror(reflecting:model).children where ["id","uploadTask","_status","lastReportErrorReason","serverStatus","contentType","uploadSuccessAt"].contains(child.label ?? "") {
                        state[child.label ?? "?"]=String(reflecting:child.value)
                        if child.label == "_status" {
                            var output=""; dump(child.value,to:&output,maxDepth:5,maxItems:35); state["status_detail"]=output
                        }
                    }
                    item["native_file_state"]=state
                }
                if let status=level.children.first(where:{$0.label=="currentImageStatus"})?.value { item["native_image_ui_status"]=String(reflecting:status) }
                mirror=level.superclassMirror
            }
        }
        views.append(item)
        for child in view.subviews { visit(child, depth + 1) }
    }
    for scene in UIApplication.shared.connectedScenes {
        if let scene = scene as? UIWindowScene {
            for window in scene.windows { visit(window, 0) }
        }
    }
    let report: [String: Any] = ["scope": "simulator-only fixture and view observation",
        "bootstrap": UserDefaults.standard.string(forKey: "DSAPIAdapter.bootstrapStatus") ?? "not reported",
        "swift_upload_errors": UserDefaults.standard.array(forKey:"DSAPIAdapter.probeSwiftUploadErrors") ?? [],
        "swift_error_hook_installed": UserDefaults.standard.bool(forKey:"DSAPIAdapter.probeSwiftErrorHookInstalled"),
        "last_attachment_error": UserDefaults.standard.string(forKey: "DSAPIAdapter.lastAttachmentError") ?? "none",
        "last_attachment_import": UserDefaults.standard.dictionary(forKey: "DSAPIAdapter.lastAttachmentImport") ?? [:],
        "last_route": UserDefaults.standard.string(forKey: "DSAPIAdapter.lastLocalRoute") ?? "none",
        "last_chat_request_summary": UserDefaults.standard.dictionary(forKey: "DSAPIAdapter.lastChatRequestSummary") ?? [:],
        "save_performed_off_main": UserDefaults.standard.bool(forKey: "DSAPIAdapter.probeSaveOffMain"),
        "account_fixture_active": UserDefaults.standard.bool(forKey: "DSAPIAdapter.accountFixtureActive"),
        "saved_api_mode": UserDefaults.standard.dictionary(forKey: "DSAPIAdapter.configuration.v1")?["enabled"] ?? false,
        "mock_configuration_saved": UserDefaults.standard.bool(forKey: "DSAPIAdapter.testConfigurationSaved"),
        "mock_keychain_bypassed": UserDefaults.standard.bool(forKey: "DSAPIAdapter.testKeychainBypassed"),
        "native_settings_items": UserDefaults.standard.array(forKey: "DSAPIAdapter.nativeSettingsItems") ?? [],
        "native_settings_source": UserDefaults.standard.dictionary(forKey: "DSAPIAdapter.nativeSettingsSource") ?? [:],
        "native_language": UserDefaults.standard.string(forKey: "DSAPIAdapter.nativeLanguage") ?? "not inferred",
        "speech_voice": UserDefaults.standard.string(forKey: "DSAPIAdapter.speechVoice") ?? "device default",
        "last_spoken_message_id": UserDefaults.standard.integer(forKey: "DSAPIAdapter.lastSpokenMessageID"),
        "speech_status": UserDefaults.standard.string(forKey: "DSAPIAdapter.speechStatus") ?? "not started",
        "last_speech_voice": UserDefaults.standard.string(forKey: "DSAPIAdapter.lastSpeechVoice") ?? "not selected",
        "last_voice_demo": UserDefaults.standard.dictionary(forKey: "DSAPIAdapter.lastVoiceDemo") ?? [:],
        "usage_snapshot": UserDefaults.standard.dictionary(forKey: "DSAPIAdapter.usage.v1") ?? [:],
        "observed_native_client_status": UserDefaults.standard.string(forKey: "DSAPIAdapter.observedNativeClientStatus") ?? "not observed",
        "actual_wire_valid": Dictionary(uniqueKeysWithValues: ["ready", "title", "delta", "finish"].map {
            ($0, UserDefaults.standard.object(forKey: "DSAPIAdapter.actualWireValid." + $0) ?? "not recorded")
        }),
        "mock_configuration_error": UserDefaults.standard.string(forKey: "DSAPIAdapter.testConfigurationError") ?? "none",
        "fixtures": results, "views": views]
    if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
       let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: directory.appendingPathComponent("DSAPI-runtime-probe.json"), options: .atomic)
    }
}
