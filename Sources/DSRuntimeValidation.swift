import Foundation
import Darwin

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

@_cdecl("DSAPICopySettingsBackingSource")
public func copySettingsBackingSource(_ raw: UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    guard let raw else { return nil }
    let source = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    let selector = NSSelectorFromString("itemIdentifierForIndexPath:")
    var visited = Set<ObjectIdentifier>()
    func find(_ value: Any, depth: Int) -> NSObject? {
        guard depth < 4 else { return nil }
        let reflected = Mirror(reflecting: value)
        if reflected.displayStyle == .optional {
            return reflected.children.first.flatMap { find($0.value, depth: depth + 1) }
        }
        if let object = value as? NSObject {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return nil }
            if object.responds(to: selector) { return object }
        }
        var mirror: Mirror? = reflected
        while let current = mirror {
            for child in current.children where !(child.label ?? "").lowercased().contains("tableview") {
                if let match = find(child.value, depth: depth + 1) { return match }
            }
            mirror = current.superclassMirror
        }
        return nil
    }
    guard let backing = find(source, depth: 0) else { return nil }
    return Unmanaged.passRetained(backing).toOpaque()
}

// A local profile uses the native User value/layout, but has no official authentication credential.
// It exists solely to drive the original UI while offline/API mode owns routes.
@_cdecl("DSAPIBeginGuest")
public func beginGuest(_ raw: UnsafeRawPointer?) -> Bool {
    guard let type=appType("DeepSeek_Chat.AppModels.User") else {
        UserDefaults.standard.set("Native User decoder unavailable",forKey:"DSAPIAdapter.guestActivationStatus"); return false
    }
    guard let symbol=dlsym(UnsafeMutableRawPointer(bitPattern:-2),"DSAPIActivateGuestUser") else {
        UserDefaults.standard.set("Native Guest bridge unavailable",forKey:"DSAPIAdapter.guestActivationStatus"); return false
    }
    let bridge=unsafeBitCast(symbol,to:(@convention(c)(UnsafeRawPointer?) -> Bool).self)
    let data:[String:Any] = ["id":"api-guest","token":"dsapi-local-guest","email":"","mobile":"","idProfiles":[],"chat":["isMuted":0],"needBirthday":false]
    do {
        let value=try JSONDecoder().decode(type,from:JSONSerialization.data(withJSONObject:data))
        func install<T>(_ user:T) -> Bool {
            UserDefaults.standard.set("Guest layout: \(String(reflecting:T.self)) / \(MemoryLayout<T>.size)",forKey:"DSAPIAdapter.guestActivationStatus")
            guard MemoryLayout<T>.size>64 else { return false }
            return withUnsafePointer(to:user) { bridge(UnsafeRawPointer($0)) }
        }
        return _openExistential(value,do:install)
    } catch {
        UserDefaults.standard.set("Guest decode failed: \(error)",forKey:"DSAPIAdapter.guestActivationStatus"); return false
    }
}
@_cdecl("DSAPILeaveGuest")
public func leaveGuest() -> Bool {
    guard let getter=dlsym(UnsafeMutableRawPointer(bitPattern:-2),"DSAPINativeAccountManager"),
          let leave=dlsym(UnsafeMutableRawPointer(bitPattern:-2),"DSAPILeaveGuestContext") else { return false }
    let get=unsafeBitCast(getter,to:(@convention(c)() -> UnsafeMutableRawPointer?).self)
    let logout=unsafeBitCast(leave,to:(@convention(c)(UnsafeMutableRawPointer?) -> Bool).self)
    guard let raw=get() else { return false }
    let manager=Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    guard let published=Mirror(reflecting:manager).children.first(where:{$0.label=="_accountContext"})?.value,
          let subject=Mirror(reflecting:published).children.first(where:{$0.label=="projectedValue"})?.value,
          let current=Mirror(reflecting:subject).children.first(where:{$0.label=="currentValue"})?.value,
          let context=Mirror(reflecting:current).children.first?.value else { return false }
    guard Mirror(reflecting:context).displayStyle == .class else { return false }
    return logout(Unmanaged.passUnretained(context as AnyObject).toOpaque())
}
@_cdecl("DSAPIGuestFooterLabel")
public func guestFooterLabel(_ raw:UnsafeRawPointer?) -> UnsafeMutableRawPointer? {
    guard let raw else { return nil }
    let view=Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    guard let label=Mirror(reflecting:view).children.first(where:{$0.label=="nameLabel"})?.value as AnyObject? else { return nil }
    return Unmanaged.passUnretained(label).toOpaque()
}

@_cdecl("DSAPIFinishGuestWelcome")
public func finishGuestWelcome(_ raw:UnsafeRawPointer?) -> Bool {
    guard let raw, let symbol=dlsym(UnsafeMutableRawPointer(bitPattern:-2),"DSAPINativeAccountManager") else { return false }
    let get=unsafeBitCast(symbol,to:(@convention(c)() -> UnsafeMutableRawPointer?).self)
    guard let managerRaw=get() else { return false }
    let manager=Unmanaged<AnyObject>.fromOpaque(managerRaw).takeUnretainedValue()
    guard let published=Mirror(reflecting:manager).children.first(where:{$0.label=="_accountContext"})?.value,
          let subject=Mirror(reflecting:published).children.first(where:{$0.label=="projectedValue"})?.value,
          let current=Mirror(reflecting:subject).children.first(where:{$0.label=="currentValue"})?.value,
          Mirror(reflecting:current).children.first != nil else { return false }
    let controller=Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    if let action=Mirror(reflecting:controller).children.first(where:{$0.label=="onBegin"})?.value as? () -> Void { action() }
    return true
}
