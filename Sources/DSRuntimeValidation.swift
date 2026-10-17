import Foundation

// Runtime lookup lets the installed application's own Decodable conformance
// validate the local identity. No original application source is linked here.
private func appType(_ name: String) -> (any Decodable.Type)? {
    if let type = _typeByName(name) as? any Decodable.Type { return type }
    let qualified = name.hasPrefix("DeepSeek_Chat.") ? String(name.dropFirst("DeepSeek_Chat.".count)) : name
    let parts = qualified.split(separator: ".").map(String.init)
    guard parts.count > 1, let leaf = parts.last else { return nil }
    let namespaces = parts.dropLast().map { "\($0.utf8.count)\($0)O" }.joined()
    return _typeByName("13DeepSeek_Chat" + namespaces + "\(leaf.utf8.count)\(leaf)V") as? any Decodable.Type
}

@_cdecl("DSAPICopyLocalUserData")
public func copyLocalUserData() -> UnsafeMutableRawPointer? {
    let names = ["DeepSeek_Chat.AppModels.User", "13DeepSeek_Chat9AppModelsO4UserV"]
    guard let type = names.compactMap({ appType($0) }).first else {
        UserDefaults.standard.set("未找到原应用的用户解码器", forKey: "DSAPIAdapter.bootstrapStatus")
        return nil
    }
    let user: [String: Any] = [
        "id": "local-api", "token": "local-api-no-official-account",
        "email": "", "mobile": "", "idProfiles": [],
        "chat": ["isMuted": 0], "needBirthday": false
    ]
    do {
        let data = try JSONSerialization.data(withJSONObject: user)
        // Decode and re-encode with the real type to preserve its persistence format.
        let value = try JSONDecoder().decode(type, from: data)
        guard let encodable = value as? any Encodable else { return nil }
        let canonical = try JSONEncoder().encode(encodable)
        UserDefaults.standard.set("本地身份已通过原应用解码器校验", forKey: "DSAPIAdapter.bootstrapStatus")
        return Unmanaged.passRetained(canonical as NSData).toOpaque()
    } catch {
        UserDefaults.standard.set("原应用拒绝本地身份数据；未注入无效上下文", forKey: "DSAPIAdapter.bootstrapStatus")
        return nil
    }
}

@_cdecl("DSAPIValidateModelData")
public func validateModelData(_ bytes: UnsafeRawPointer?, _ length: Int, _ cName: UnsafePointer<CChar>?) -> Bool {
    guard let bytes, let cName, length >= 0 else { return false }
    guard let type = appType(String(cString: cName)) else { return false }
    do {
        _ = try JSONDecoder().decode(type, from: Data(bytes: bytes, count: length))
        return true
    } catch { return false }
}

@_cdecl("DSAPINativeSpeechMessageID")
public func nativeSpeechMessageID(_ raw: UnsafeRawPointer?) -> Int64 {
    guard let raw else { return 0 }
    let object = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    func unwrap(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional ? mirror.children.first?.value : value
    }
    var mirror: Mirror? = Mirror(reflecting: object)
    while let current = mirror {
        if let stored = current.children.first(where: { $0.label == "lastMessage" }),
           let message = unwrap(stored.value),
           let identifier = Mirror(reflecting: message).children.first(where: { $0.label == "id" })?.value {
            if let number = identifier as? Int { return Int64(number) }
            if let number = identifier as? Int64 { return number }
        }
        mirror = current.superclassMirror
    }
    return 0
}
