import XCTest

final class CaptureTests: XCTestCase {
    private func openNativeApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.deepseek.chat")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        capture(app, "initial")
        // This is a fresh, disposable test installation. Accept only a known
        // welcome agreement; do not interact with sign-in or system permissions.
        let agreementLabels = ["Agree and Continue", "Agree & Continue", "I Agree",
                               "同意并继续", "同意并使用", "同意"]
        for label in agreementLabels {
            let button = app.buttons[label].firstMatch
            if button.exists && button.isHittable {
                button.tap()
                Thread.sleep(forTimeInterval: 2)
                break
            }
        }
        for label in ["Start Chat", "开始聊天", "开始对话", "开始使用"] {
            let text = app.staticTexts[label].firstMatch
            if text.exists && text.isHittable {
                text.tap()
                Thread.sleep(forTimeInterval: 3)
                break
            }
        }
        capture(app, "after-optional-welcome")
        print("DSAPI_UI_HIERARCHY_BEGIN\n" + String(app.debugDescription.prefix(24000)) + "\nDSAPI_UI_HIERARCHY_END")
        return app
    }

    func testNativeSettings() throws {
        let app = openNativeApp()
        continueAfterFailure = true
        let settingsVisited = inspectSettings(app)
        print("DSAPI_API_SETTINGS_VISITED=\(settingsVisited)")
        #if DSAPI_ADAPTER_UI
        XCTAssertTrue(settingsVisited, "The settings entry and API configuration must both be reachable")
        #endif
    }

    func testNativeApp() throws {
        let app = openNativeApp()
        #if DSAPI_MOCK_UI
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let input = app.textViews.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15), "Original chat input is missing")
        input.tap()
        input.typeText("API integration test")
        Thread.sleep(forTimeInterval: 1)
        let sendNames = ["send", "Send", "Send message", "send_message", "发送", "发送消息"]
        let named = sendNames.map { app.buttons[$0].firstMatch }.first { $0.exists && $0.isHittable }
        if let send = named {
            send.tap()
        } else {
            // The supplied 2.6.2 layout places its trailing action 20 points
            // inside the input's right edge and 32 points below its text row.
            let point = app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: input.frame.maxX-20, dy: input.frame.maxY+32))
            point.tap()
        }
        let reply = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "流式输出正常", "流式输出正常")).firstMatch
        let firstPart = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "首段流式回复", "首段流式回复")).firstMatch
        let firstReceived = firstPart.waitForExistence(timeout: 15)
        if !firstReceived {
            capture(app, "streaming-failure")
            print("DSAPI_CHAT_FAILURE_BEGIN\n" + String(app.debugDescription.suffix(24000)) + "\nDSAPI_CHAT_FAILURE_END")
        }
        XCTAssertTrue(firstReceived, "The first streamed fragment was not rendered")
        capture(app, "streaming-first-part")
        XCTAssertFalse(reply.exists, "The first fragment was only visible after the complete reply")
        let received = reply.waitForExistence(timeout: 25)
        capture(app, "mock-api-reply")
        print("DSAPI_CHAT_HIERARCHY_BEGIN\n" + String(app.debugDescription.suffix(24000)) + "\nDSAPI_CHAT_HIERARCHY_END")
        XCTAssertTrue(received, "The original UI did not render the mock API reply")
        let readAloud = app.buttons["DSAPI.ReadAloud"].firstMatch
        XCTAssertTrue(readAloud.waitForExistence(timeout: 10), "Original read-aloud button is missing")
        capture(app, "completed-native-reply")
        #endif
    }


    private func openExistingTestChat() -> XCUIApplication {
        let app = openNativeApp()
        if !app.buttons["DSAPI.ReadAloud"].allElementsBoundByIndex.contains(where: { $0.isHittable }) {
            let sidebar = app.buttons["open_sidebar"].firstMatch
            XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
            sidebar.tap()
            let session = app.collectionViews.cells.containing(.staticText, identifier: "API integration test").firstMatch
            XCTAssertTrue(session.waitForExistence(timeout: 10), "The completed native session was not persisted")
            session.tap()
        }
        return app
    }

    func testNativeCancellation() throws {
        #if DSAPI_MOCK_UI
        let app = openExistingTestChat()
        let followup=app.textViews.allElementsBoundByIndex.first {
            $0.isHittable && $0.isEnabled && $0.frame.minY > app.frame.height*0.5 && (($0.value as? String) ?? "").isEmpty
        }
        XCTAssertNotNil(followup, "Native input could not be found for a second turn")
        followup?.tap()
        followup?.typeText("API cancellation test")
        let send=app.buttons["Send"].firstMatch
        if send.exists && send.isHittable { send.tap() }
        else if let field=followup {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: field.frame.maxX-20, dy: field.frame.maxY+32)).tap()
        }
        let partial=app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "取消前片段", "取消前片段")).firstMatch
        XCTAssertTrue(partial.waitForExistence(timeout: 15), "Second-turn stream did not begin")
        capture(app, "before-stop-generation")
        let stopNames=["Stop generating", "Stop", "停止生成", "停止"]
        if let stop=stopNames.map({ app.buttons[$0].firstMatch }).first(where: { $0.exists && $0.isHittable }) {
            stop.tap()
        } else if let field=followup {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: field.frame.maxX-20, dy: field.frame.maxY+32)).tap()
        }
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(partial.exists, "Stopping generation discarded the already rendered text")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "取消后不应出现", "取消后不应出现")).firstMatch.exists)
        capture(app, "after-stop-generation")
        #endif
    }

    func testNativeReadAloud() throws {
        #if DSAPI_MOCK_UI
        let app = openExistingTestChat()
        let visibleRead = NSPredicate { _, _ in app.buttons["DSAPI.ReadAloud"].allElementsBoundByIndex.contains(where: { $0.isHittable }) }
        expectation(for: visibleRead, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        let readAloud = try XCTUnwrap(app.buttons["DSAPI.ReadAloud"].allElementsBoundByIndex.first(where: { $0.isHittable }), "Original read-aloud button is missing")
        readAloud.tap()
        let speaking=app.buttons.matching(NSPredicate(format: "identifier == %@ AND (label == %@ OR label == %@)",
            "DSAPI.ReadAloud", "Stop reading", "停止朗读")).firstMatch
        XCTAssertTrue(speaking.waitForExistence(timeout: 15), "Read-aloud did not reach its active state")
        capture(app, "read-aloud-started")
        print("DSAPI_READ_ALOUD_LABEL=\(readAloud.label)")
        readAloud.tap()
        capture(app, "read-aloud-stopped")
        #endif
    }

    func testNativeRegeneration() throws {
        #if DSAPI_MOCK_UI
        let app = openNativeApp()
        let input = app.textViews.allElementsBoundByIndex.first { $0.isHittable && $0.isEnabled && $0.frame.minY > app.frame.height*0.5 }
        let field = try XCTUnwrap(input, "Native input is missing")
        field.tap(); field.typeText("API regeneration test")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: field.frame.maxX-20, dy: field.frame.maxY+32)).tap()
        let visibleRegenerate = NSPredicate { _, _ in app.buttons["Regenerate"].allElementsBoundByIndex.contains { $0.isHittable } }
        expectation(for: visibleRegenerate, evaluatedWith: app)
        waitForExpectations(timeout: 30)
        let regenerate = try XCTUnwrap(app.buttons["Regenerate"].allElementsBoundByIndex.first { $0.isHittable })
        capture(app, "before-native-regeneration")
        regenerate.tap()
        let stop = app.buttons["Stop"].firstMatch
        let started = stop.waitForExistence(timeout: 10)
        capture(app, "native-regeneration-started")
        print("DSAPI_REGENERATION_BEGIN\n" + String(app.debugDescription.suffix(24000)) + "\nDSAPI_REGENERATION_END")
        XCTAssertTrue(started, "Original regenerate action did not start a new stream")
        expectation(for: NSPredicate { _, _ in !app.buttons["Stop"].allElementsBoundByIndex.contains { $0.isHittable } }, evaluatedWith: app)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "流式输出正常")).firstMatch.exists)
        capture(app, "native-regeneration-finished")
        #endif
    }

    private func inspectSettings(_ app: XCUIApplication) -> Bool {
        let sidebar = app.buttons["open_sidebar"].firstMatch
        if sidebar.exists && sidebar.isHittable {
            sidebar.tap()
            Thread.sleep(forTimeInterval: 1)
            capture(app, "sidebar")
            print("DSAPI_SIDEBAR_BEGIN\n" + String(app.debugDescription.suffix(24000)) + "\nDSAPI_SIDEBAR_END")
            #if DSAPI_ADAPTER_UI
            let directSettings = app.buttons["DSAPI.SettingsEntry"].firstMatch
            XCTAssertTrue(directSettings.exists && directSettings.isHittable, "Sidebar footer must be a Settings entry")
            XCTAssertFalse(directSettings.label.localizedCaseInsensitiveContains("profile"))
            XCTAssertFalse(app.images["sidebar/userAvatar"].firstMatch.isHittable, "Account avatar must be removed")
            #endif
            let settings = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS %@", "setting", "profile", "设置")).firstMatch
            if settings.exists && settings.isHittable {
                settings.tap()
                Thread.sleep(forTimeInterval: 1)
                capture(app, "original-settings")
                print("DSAPI_SETTINGS_HIERARCHY_BEGIN\n" + String(app.debugDescription.suffix(24000)) + "\nDSAPI_SETTINGS_HIERARCHY_END")
                #if DSAPI_ADAPTER_UI
                for name in ["Account settings", "Account Settings", "Account management", "Account Management", "账号管理", "帳戶管理", "帳號管理", "Log out", "Log Out", "退出登录", "登出", "Help & Feedback", "帮助与反馈", "Service agreement", "服务协议"] {
                    XCTAssertFalse(app.staticTexts[name].firstMatch.exists, "Removed setting is still present: \(name)")
                }
                let usage = app.cells["DSAPI.Usage"].firstMatch
                XCTAssertTrue(usage.exists && usage.isHittable, "Data controls must become API Usage")
                usage.tap()
                capture(app, "usage-dashboard")
                print("DSAPI_USAGE_BEGIN\n" + String(app.debugDescription.suffix(16000)) + "\nDSAPI_USAGE_END")
                let closeUsage = app.buttons["DSAPI.CloseUsage"].firstMatch
                XCTAssertTrue(closeUsage.waitForExistence(timeout: 5) && closeUsage.isHittable)
                closeUsage.tap()
                XCTAssertTrue(app.cells["DSAPI.VoicePicker"].firstMatch.waitForExistence(timeout: 5))
                inspectNativePreferences(app)
                #endif
                let knownAPI = app.buttons["DSAPI.APISettings"].firstMatch
                let api = knownAPI.exists ? knownAPI : app.buttons["API"].firstMatch
                if api.exists && api.isHittable {
                    api.tap()
                    XCTAssertTrue(app.textFields["Base URL"].waitForExistence(timeout: 5))
                    XCTAssertTrue(app.secureTextFields["API Key"].exists)
                    capture(app, "api-settings")
                    return true
                }
            }
        }
        return false
    }

    private func inspectNativePreferences(_ app: XCUIApplication) {
        let voice = app.cells["DSAPI.VoicePicker"].firstMatch
        XCTAssertTrue(voice.exists && voice.isHittable, "Native voice setting must be reachable")
        if voice.exists && voice.isHittable {
            voice.tap()
            let picker = app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable })
            let choice = picker?.cells.firstMatch ?? app.cells["tts-voice-picker-cell"].firstMatch
            let opened = choice.waitForExistence(timeout: 15)
            capture(app, "original-voice-picker")
            print("DSAPI_VOICE_PICKER_BEGIN\n" + String(app.debugDescription.suffix(18000)) + "\nDSAPI_VOICE_PICKER_END")
            XCTAssertTrue(opened, "Original voice picker did not load device voices")
            if opened { choice.swipeLeft(); Thread.sleep(forTimeInterval: 1) }
            let confirm = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "Confirm", "确认")).firstMatch
            if confirm.exists && confirm.isHittable { confirm.tap() }
            else {
                let close = app.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label == %@", "close", "关闭")).firstMatch
                if close.exists && close.isHittable { close.tap() }
            }
        }
        for names in [["Font size", "字体大小", "字體大小"], ["Personalization", "个性化", "個人化"], ["Language", "语言", "語言"]] {
            let found = names.map({ app.staticTexts[$0].firstMatch }).first(where: { $0.exists && $0.isHittable })
            XCTAssertNotNil(found, "Native preference is unreachable: \(names[0])")
            guard let entry = found else { continue }
            entry.tap()
            Thread.sleep(forTimeInterval: 1)
            capture(app, "preference-" + names[0])
            print("DSAPI_PREFERENCE_\(names[0])_BEGIN\n" + String(app.debugDescription.suffix(18000)) + "\nDSAPI_PREFERENCE_END")
            var expectedValue: String?
            if names[0] == "Font size" {
                let follow = app.switches.firstMatch
                if follow.exists && (follow.value as? String) == "1" { follow.tap() }
                let slider = nativeFontControl(app)
                XCTAssertTrue(slider.exists && slider.isHittable, "Native font size control is missing")
                let previous = slider.value as? String
                if slider.elementType == .slider { slider.adjust(toNormalizedSliderPosition: 0.7) }
                else {
                    slider.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
                    let changed = NSPredicate { _, _ in (slider.value as? String) != previous }
                    expectation(for: changed, evaluatedWith: slider)
                    waitForExpectations(timeout: 15)
                }
                expectedValue = slider.value as? String
                XCTAssertNotEqual(expectedValue, previous, "Native font size did not change")
                print("DSAPI_FONT_CHANGE=\(previous ?? "unknown")->\(slider.value as? String ?? "unknown")")
                capture(app, "font-size-adjusted")
            }
            if names[0] == "Personalization" {
                let toggle = app.switches.firstMatch
                XCTAssertTrue(toggle.exists, "Native personalization switch is missing")
                let previous = toggle.value as? String
                toggle.tap()
                XCTAssertNotEqual(toggle.value as? String, previous, "Personalization did not change")
                expectedValue = toggle.value as? String
            }
            if names[0] == "Language" {
                let chineseNames = ["简体中文", "中文（简体）", "Chinese, Simplified", "Chinese (Simplified)", "Simplified Chinese"]
                let chinese = chineseNames.map { app.staticTexts[$0].firstMatch }.first { $0.exists && $0.isHittable }
                XCTAssertNotNil(chinese, "Native Simplified Chinese language option is missing")
                chinese?.tap()
                Thread.sleep(forTimeInterval: 2)
                capture(app, "settings-after-language-change")
                print("DSAPI_LANGUAGE_CHANGED_BEGIN\n" + String(app.debugDescription.suffix(24000)) + "\nDSAPI_LANGUAGE_CHANGED_END")
                XCTAssertTrue(app.staticTexts["语言"].firstMatch.exists, "Original settings did not switch to Chinese")
                XCTAssertTrue(app.staticTexts["用量统计"].firstMatch.exists, "Usage entry did not follow app language")
                for forbidden in ["账号管理", "退出登录", "服务协议", "帮助与反馈"] {
                    XCTAssertFalse(app.staticTexts[forbidden].firstMatch.isHittable, "Removed item returned after changing language: \(forbidden)")
                }
                app.terminate()
                app.launch()
                let sidebar = app.buttons["open_sidebar"].firstMatch
                if sidebar.waitForExistence(timeout: 10) { sidebar.tap() }
                let settings = app.buttons["DSAPI.SettingsEntry"].firstMatch
                XCTAssertEqual(settings.label, "设置", "Sidebar settings label did not retain app language")
                capture(app, "sidebar-after-language-change")
                if settings.exists && settings.isHittable { settings.tap() }
            } else {
                backFromNativePreference(app)
                if let expected = expectedValue {
                    let revisit = names.map({ app.staticTexts[$0].firstMatch }).first { $0.exists && $0.isHittable }
                    XCTAssertNotNil(revisit, "Preference could not be reopened for persistence verification")
                    revisit?.tap()
                    let control = names[0] == "Font size" ? nativeFontControl(app) : app.switches.firstMatch
                    XCTAssertTrue(control.waitForExistence(timeout: 5))
                    XCTAssertEqual(control.value as? String, expected, "Native preference did not persist after reopening")
                    backFromNativePreference(app)
                }
            }
        }
    }

    private func nativeFontControl(_ app: XCUIApplication) -> XCUIElement {
        if let slider = app.sliders.allElementsBoundByIndex.first(where: { $0.isHittable }) { return slider }
        let custom = app.otherElements["DSAPI.NativeFontSlider"].firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 15), "Original custom font control was not observed")
        return custom
    }

    private func backFromNativePreference(_ app: XCUIApplication) {
        guard let navigation = app.navigationBars.allElementsBoundByIndex.last else {
            XCTFail("Native preference navigation bar is missing"); return
        }
        if let button = navigation.buttons.allElementsBoundByIndex.first(where: { $0.isHittable }) { button.tap() }
        else { navigation.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap() }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
