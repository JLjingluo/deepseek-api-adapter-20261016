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
        capture(app, "after-welcome")
        print("DSAPI_UI_HIERARCHY_BEGIN\n" + String(app.debugDescription.prefix(24000)) + "\nDSAPI_UI_HIERARCHY_END")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
