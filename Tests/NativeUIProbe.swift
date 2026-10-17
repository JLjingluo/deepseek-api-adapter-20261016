import XCTest

final class CaptureTests: XCTestCase {
    func testNativeApp() throws {
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
        let settingsVisited = inspectSettings(app)
        print("DSAPI_API_SETTINGS_VISITED=\(settingsVisited)")
        #if DSAPI_MOCK_UI
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let input = app.textViews.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15), "Original chat input is missing")
        input.tap()
        input.typeText("API 接入测试")
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
        let received = reply.waitForExistence(timeout: 25)
        capture(app, "mock-api-reply")
        print("DSAPI_CHAT_HIERARCHY_BEGIN\n" + String(app.debugDescription.suffix(24000)) + "\nDSAPI_CHAT_HIERARCHY_END")
        XCTAssertTrue(received, "The original UI did not render the mock API reply")
        #endif
    }

    private func inspectSettings(_ app: XCUIApplication) -> Bool {
        let sidebar = app.buttons["open_sidebar"].firstMatch
        if sidebar.exists && sidebar.isHittable {
            sidebar.tap()
            Thread.sleep(forTimeInterval: 1)
            capture(app, "sidebar")
            print("DSAPI_SIDEBAR_BEGIN\n" + String(app.debugDescription.suffix(24000)) + "\nDSAPI_SIDEBAR_END")
            let settings = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS %@", "setting", "profile", "设置")).firstMatch
            if settings.exists && settings.isHittable {
                settings.tap()
                Thread.sleep(forTimeInterval: 1)
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

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
