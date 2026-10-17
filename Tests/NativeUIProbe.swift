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
        readAloud.tap()
        Thread.sleep(forTimeInterval: 1)
        capture(app, "read-aloud-started")
        print("DSAPI_READ_ALOUD_LABEL=\(readAloud.label)")
        readAloud.tap()
        capture(app, "read-aloud-stopped")
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
                for name in ["Account management", "Account Management", "账号管理", "帳戶管理", "Log out", "Log Out", "退出登录", "登出", "Help & Feedback", "帮助与反馈", "Service agreement", "服务协议"] {
                    XCTAssertFalse(app.staticTexts[name].firstMatch.isHittable, "Removed setting is still reachable: \(name)")
                }
                let usage = app.cells["DSAPI.Usage"].firstMatch
                XCTAssertTrue(usage.exists && usage.isHittable, "Data controls must become API Usage")
                usage.tap()
                capture(app, "usage-dashboard")
                print("DSAPI_USAGE_BEGIN\n" + String(app.debugDescription.suffix(16000)) + "\nDSAPI_USAGE_END")
                app.navigationBars.buttons.firstMatch.tap()
                inspectNativePreferences(app)
                #endif
                let api = app.buttons["API"].firstMatch
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
        for names in [["Font size", "字体大小", "字體大小"], ["Personalization", "个性化", "個人化"], ["Language", "语言", "語言"]] {
            guard let entry = names.map({ app.staticTexts[$0].firstMatch }).first(where: { $0.exists && $0.isHittable }) else { continue }
            entry.tap()
            Thread.sleep(forTimeInterval: 1)
            capture(app, "preference-" + names[0])
            print("DSAPI_PREFERENCE_\(names[0])_BEGIN\n" + String(app.debugDescription.suffix(18000)) + "\nDSAPI_PREFERENCE_END")
            if names[0] == "Font size" {
                let slider = app.sliders.firstMatch
                XCTAssertTrue(slider.exists, "Native font size slider is missing")
                slider.adjust(toNormalizedSliderPosition: 0.7)
                capture(app, "font-size-adjusted")
            }
            if names[0] == "Personalization" {
                let toggle = app.switches.firstMatch
                XCTAssertTrue(toggle.exists, "Native personalization switch is missing")
                let previous = toggle.value as? String
                toggle.tap()
                XCTAssertNotEqual(toggle.value as? String, previous, "Personalization did not change")
            }
            if names[0] == "Language" {
                // Observe the exact native language picker before choosing a
                // language in a subsequent round; do not dismiss by guessing.
                app.terminate()
                app.launch()
                let sidebar = app.buttons["open_sidebar"].firstMatch
                if sidebar.waitForExistence(timeout: 10) { sidebar.tap() }
                let settings = app.buttons["DSAPI.SettingsEntry"].firstMatch
                if settings.exists && settings.isHittable { settings.tap() }
            } else {
                app.navigationBars.buttons.firstMatch.tap()
            }
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
