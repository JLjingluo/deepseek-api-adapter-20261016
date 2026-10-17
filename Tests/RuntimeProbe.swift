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
    let fixtures: [(String, Any)] = [
        ("AppModels.User", ["id": "local-api", "token": "local-api-no-official-account", "email": "",
            "mobile": "", "idProfiles": [], "chat": ["isMuted": 0], "needBirthday": false]),
        ("ServerModels.Session", session), ("ServerModels.Message", message),
        ("ServerModels.Completion.ReadyChunk", ["request_message_id": 1, "response_message_id": 2,
            "model_type": "default", "request_content": "测试", "ban_edit": false]),
        ("ServerModels.Completion.TitleChunk", ["content": "新对话"]),
        ("ServerModels.Completion.FinishChunk", [String: Any]()),
        ("ServerModels.POV", ["p": "response", "o": "SET", "v": message]),
        ("ServerModels.Response.ClientSettings", ["version": 0, "settings": [:]]),
        ("ServerModels.Response.ChatSessionFetchPage", ["chat_sessions": [session], "has_more": false]),
        ("ServerModels.Response.ChatHistoryMessages", ["chat_session": session, "chat_messages": [message],
            "cache_control": "replace", "cache_reset_at": 0])
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
        if let label = view as? UILabel { item["text"] = label.text ?? "" }
        if let button = view as? UIButton { item["title"] = button.title(for: .normal) ?? "" }
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
        "last_route": UserDefaults.standard.string(forKey: "DSAPIAdapter.lastLocalRoute") ?? "none",
        "fixtures": results, "views": views]
    if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
       let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: directory.appendingPathComponent("DSAPI-runtime-probe.json"), options: .atomic)
    }
}
