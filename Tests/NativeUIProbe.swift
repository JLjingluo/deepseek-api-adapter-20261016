import XCTest
import UIKit

final class CaptureTests: XCTestCase {
    private func openNativeApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.deepseek.chat")
        app.terminate(); app.launch()
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

    private func openAPISettings(_ app:XCUIApplication) {
        XCTAssertTrue(openOriginalSettings(app))
        let api=app.cells["DSAPI.APISettings"].firstMatch
        XCTAssertTrue(reveal(app,api)); capture(app,"native-api-list-entry"); api.tap()
        XCTAssertTrue(app.switches["DSAPI.Enabled"].firstMatch.waitForExistence(timeout:10))
    }

    func testNativeAPIErrors() throws {
        #if DSAPI_MOCK_UI
        let app=openNativeApp()
        for status in [401,402] {
            let input=try XCTUnwrap(app.textViews.allElementsBoundByIndex.filter { $0.isHittable && $0.isEnabled }.max { $0.frame.maxY < $1.frame.maxY })
            enterPrompt("API diagnostic \(status) test",into:input,in:app)
            app.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","Send","发送")).firstMatch.tap()
            let alert=app.alerts.firstMatch; XCTAssertTrue(alert.waitForExistence(timeout:25))
            XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","HTTP \(status)")).firstMatch.exists)
            capture(app,"actionable-api-error-\(status)")
            alert.buttons["Copy details"].tap()
            let copied=UIPasteboard.general.string ?? ""
            XCTAssertTrue(copied.contains("\(status)") && copied.contains("provider_request"))
            XCTAssertFalse(copied.contains("ci-dummy-key") || copied.contains("API diagnostic"))
        }
        openAPISettings(app)
        let test=app.cells["DSAPI.TestConnection"].staticTexts.firstMatch
        XCTAssertTrue(reveal(app,test)); test.tap()
        let success=app.alerts["Connection succeeded"].firstMatch
        XCTAssertTrue(success.waitForExistence(timeout:25)); capture(app,"saved-api-connection-test")
        success.buttons.firstMatch.tap(); app.buttons["DSAPI.Cancel"].tap()
        #endif
    }

    func testNativeAPIOptions() throws {
        #if DSAPI_MOCK_UI
        let app=openNativeApp(); openAPISettings(app)
        let show=app.switches["DSAPI.ShowInChat"].firstMatch
        XCTAssertTrue(show.exists && show.isHittable)
        if (show.value as? String) != "1" { show.tap() }
        app.buttons["DSAPI.Save"].tap()
        XCTAssertTrue(app.switches["DSAPI.Enabled"].firstMatch.waitForNonExistence(timeout:10))
        app.terminate(); app.launch(); XCTAssertTrue(app.wait(for:.runningForeground,timeout:20))
        app.buttons["open_sidebar"].tap()
        let entry=app.buttons["DSAPI.ConversationAPI"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout:10)); XCTAssertTrue(entry.isHittable)
        let accountAvatar=app.images["sidebar/userAvatar"].firstMatch
        XCTAssertTrue(accountAvatar.exists)
        XCTAssertLessThanOrEqual(entry.frame.maxY,accountAvatar.frame.minY+8,"API row overlaps the original account row")
        capture(app,"sidebar-api-and-account")
        let originalArguments=app.launchArguments
        app.terminate(); app.launchArguments=originalArguments+["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN"]; app.launch()
        XCTAssertTrue(app.wait(for:.runningForeground,timeout:20)); app.buttons["open_sidebar"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout:10)); capture(app,"sidebar-api-and-account-chinese")
        app.terminate(); app.launchArguments=originalArguments; app.launch()
        XCTAssertTrue(app.wait(for:.runningForeground,timeout:20)); app.buttons["open_sidebar"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout:10)); entry.tap()
        XCTAssertTrue(app.switches["DSAPI.Enabled"].firstMatch.waitForExistence(timeout:10))
        let automatic=app.switches["DSAPI.AutomaticModels"].firstMatch
        XCTAssertTrue(reveal(app,automatic))
        if (automatic.value as? String) != "1" { automatic.tap() }
        let fetch=app.cells["DSAPI.FetchModels"].staticTexts.firstMatch; XCTAssertTrue(reveal(app,fetch)); fetch.tap()
        let choice=app.staticTexts["ci-mock-reasoner"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout:25)); capture(app,"automatic-model-list"); choice.tap()
        let model=app.textFields["Model"].firstMatch
        XCTAssertTrue(reveal(app,model,up:false)); XCTAssertEqual(model.value as? String,"ci-mock-reasoner")
        model.tap(); dismissKeyboardHelp(app); model.typeText("-manual\n"); dismissKeyboardHelp(app); XCTAssertTrue((model.value as? String)?.hasSuffix("-manual")==true)
        dismissKeyboardHelp(app)
        let effort=app.cells["DSAPI.Effort"].firstMatch; let effortTitle=effort.staticTexts.firstMatch; XCTAssertTrue(reveal(app,effortTitle)); effortTitle.tap()
        let maxOption=app.buttons["Max"].firstMatch
        XCTAssertTrue(maxOption.waitForExistence(timeout:10)); maxOption.tap(); XCTAssertTrue(effort.staticTexts["Max"].exists)
        let provider=app.cells["DSAPI.Provider"].staticTexts.firstMatch; XCTAssertTrue(reveal(app,provider,up:false)); provider.tap()
        app.buttons["OpenAI / ChatGPT"].firstMatch.tap()
        XCTAssertTrue(reveal(app,app.textFields["Base URL"])); XCTAssertEqual(app.textFields["Base URL"].value as? String,"https://api.openai.com/v1")
        XCTAssertTrue(reveal(app,app.secureTextFields["API Key"]))
        let key=app.secureTextFields["API Key"].value as? String
        XCTAssertTrue(key==nil || key=="" || key=="API Key","Preset must not copy a key to another provider")
        capture(app,"provider-preset-without-key")
        app.buttons["DSAPI.Cancel"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout:10)); entry.tap()
        XCTAssertTrue(app.switches["DSAPI.ShowInChat"].firstMatch.waitForExistence(timeout:10))
        app.switches["DSAPI.ShowInChat"].firstMatch.tap(); app.buttons["DSAPI.Save"].tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout:10),"Hidden shortcut remains after saving, before restart")
        capture(app,"sidebar-api-option-off-without-restart")
        app.terminate(); app.launch(); XCTAssertTrue(app.wait(for:.runningForeground,timeout:20)); app.buttons["open_sidebar"].tap()
        XCTAssertFalse(app.buttons["DSAPI.ConversationAPI"].firstMatch.exists)
        capture(app,"sidebar-api-option-off")
        app.terminate()
        #endif
    }

    func testNativeZCloudHistory() throws {
        #if DSAPI_MOCK_UI
        let app=openNativeApp(); app.buttons["open_sidebar"].tap()
        let history=app.staticTexts["Cloud history fixture"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout:15)); history.tap()
        let oldReply=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@","earlier answer","earlier answer")).firstMatch
        XCTAssertTrue(oldReply.waitForExistence(timeout:15)); capture(app,"original-history-in-api-mode")
        let input=try XCTUnwrap(app.textViews.allElementsBoundByIndex.filter { $0.isHittable && $0.isEnabled }.max { $0.frame.maxY < $1.frame.maxY }); enterPrompt("API cloud continuation test",into:input,in:app)
        app.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","Send","发送")).firstMatch.tap()
        let reply=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@","流式输出正常","流式输出正常")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout:35)); capture(app,"cloud-history-api-continuation")
        app.terminate(); app.launch(); XCTAssertTrue(app.wait(for:.runningForeground,timeout:20)); app.buttons["open_sidebar"].tap()
        XCTAssertTrue(history.waitForExistence(timeout:15)); history.tap(); XCTAssertTrue(reply.waitForExistence(timeout:15),"Refreshing original history discarded API replies")
        capture(app,"cloud-history-after-refresh")
        #endif
    }

    #if DSAPI_GUEST_UI
    func testNativeGuest() throws {
        continueAfterFailure=false
        let app=XCUIApplication(bundleIdentifier:"com.deepseek.chat"); app.launch()
        XCTAssertTrue(app.wait(for:.runningForeground,timeout:20))
        let skip=app.buttons["DSAPI.SkipLogin"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout:10)); capture(app,"skip-login-choice"); skip.tap()
        XCTAssertTrue(app.buttons["open_sidebar"].firstMatch.waitForExistence(timeout:25),"Local guest entry did not reach the original conversation UI")
        #if DSAPI_GUEST_ORIGINAL
        let guestInput=try XCTUnwrap(app.textViews.allElementsBoundByIndex.filter { $0.isHittable && $0.isEnabled }.max { $0.frame.maxY < $1.frame.maxY })
        enterPrompt("guest sign in prompt test",into:guestInput,in:app)
        app.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","Send","发送")).firstMatch.tap()
        let alert=app.alerts.firstMatch; XCTAssertTrue(alert.waitForExistence(timeout:15)); capture(app,"guest-sign-in-or-api")
        let useAPI=alert.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","Use API","使用 API")).firstMatch
        XCTAssertTrue(useAPI.exists); useAPI.tap()
        let enabled=app.switches["DSAPI.Enabled"].firstMatch; XCTAssertTrue(enabled.waitForExistence(timeout:10)); if (enabled.value as? String) != "1" { enabled.tap() }
        app.buttons["DSAPI.Save"].tap(); let restart=app.alerts.firstMatch; XCTAssertTrue(restart.waitForExistence(timeout:10)); restart.buttons.firstMatch.tap()
        app.terminate(); app.launch(); XCTAssertTrue(app.wait(for:.runningForeground,timeout:20))
        // The original post-login first-use welcome can appear after local
        // profile persistence. Accept its normal Start Chat control explicitly.
        for label in ["Start Chat","开始聊天","开始对话","开始使用"] {
            let start=app.staticTexts[label].firstMatch
            if start.waitForExistence(timeout:2) && start.isHittable { start.tap(); break }
        }
        XCTAssertTrue(app.buttons["open_sidebar"].firstMatch.waitForExistence(timeout:20))
        #endif
        let input=try XCTUnwrap(app.textViews.allElementsBoundByIndex.filter { $0.isHittable && $0.isEnabled }.max { $0.frame.maxY < $1.frame.maxY })
        enterPrompt("API integration test",into:input,in:app)
        app.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","Send","发送")).firstMatch.tap()
        let reply=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@","流式输出正常","流式输出正常")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout:35),"Guest API chat did not render without an account fixture")
        capture(app,"guest-api-chat-without-account")
        XCTAssertTrue(openOriginalSettings(app),"Local Guest must retain access to normal settings")
        let account=app.staticTexts.matching(NSPredicate(format:"label == %@ OR label == %@ OR label == %@","Account settings","账号管理","帳號管理")).firstMatch
        XCTAssertTrue(account.exists && account.isHittable); account.tap()
        let prompt=app.alerts.firstMatch; XCTAssertTrue(prompt.waitForExistence(timeout:10))
        let signIn=prompt.buttons.matching(NSPredicate(format:"label == %@ OR label == %@ OR label == %@","Sign in","登录","登入")).firstMatch
        XCTAssertTrue(signIn.exists); signIn.tap()
        let originalLogin=app.buttons.matching(NSPredicate(format:"label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@","Password","密码","密碼")).firstMatch
        XCTAssertTrue(originalLogin.waitForExistence(timeout:20),"Original sign-in page was not restored after leaving local Guest")
        capture(app,"original-login-retained-after-guest")
    }
    #endif

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


    func testNativeAttachment() throws {
        #if DSAPI_MOCK_UI
        try runNativeImage(prompt:"API image test",expected:"图片已由 API 接收")
        #endif
    }
    #if DSAPI_LIVE_UI
    func testNativeDirectAPISetup() throws {
        let app=openNativeApp(); openAPISettings(app)
        let key=app.secureTextFields["API Key"].firstMatch
        XCTAssertTrue(reveal(app,key))
        let keyReady=XCTNSPredicateExpectation(predicate:NSPredicate { _, _ in key.isEnabled },object:app)
        XCTAssertEqual(XCTWaiter.wait(for:[keyReady],timeout:30),.completed)
        key.press(forDuration:1.2); _=dismissKeyboardHelp(app)
        let paste=app.menuItems["Paste"].firstMatch.exists ? app.menuItems["Paste"].firstMatch : app.buttons["Paste"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout:5)); paste.tap()
        let allow=XCUIApplication(bundleIdentifier:"com.apple.springboard").buttons["Allow Paste"].firstMatch
        if allow.exists && allow.isHittable { allow.tap() }
        // Never type, print, compare, or capture the actual credential in XCTest.
        let pastedValue=(key.value as? String) ?? ""; XCTAssertTrue(!pastedValue.isEmpty && pastedValue != "API Key")
        if app.keyboards.firstMatch.exists { key.typeText("\n") }
        let base=app.textFields["Base URL"].firstMatch
        XCTAssertTrue(reveal(app,base,up:false)); base.tap()
        let oldBase=(base.value as? String) ?? ""
        base.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:oldBase.count)+"https://api.deepseek.com/v1\n")
        let model=app.textFields["Model"].firstMatch; XCTAssertTrue(reveal(app,model)); model.tap()
        let oldModel=(model.value as? String) ?? ""
        model.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:oldModel.count)+"deepseek-chat\n")
        let enabled=app.switches["DSAPI.Enabled"].firstMatch; XCTAssertTrue(reveal(app,enabled,up:false))
        if (enabled.value as? String) != "1" { enabled.tap() }
        app.buttons["DSAPI.Save"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:15))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Restart")).firstMatch.exists,"Real Keychain save did not reach restart confirmation")
        app.alerts.buttons.firstMatch.tap()
        app.terminate(); app.launch(); XCTAssertTrue(app.wait(for:.runningForeground,timeout:20))
        // Re-open the settings page after a genuine process relaunch. The key
        // field now comes from the production Security.framework implementation.
        openAPISettings(app)
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate { _, _ in app.buttons["DSAPI.Save"].firstMatch.isEnabled },object:app)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:15),.completed)
        let restoredValue=(app.secureTextFields["API Key"].firstMatch.value as? String) ?? ""; XCTAssertTrue(!restoredValue.isEmpty && restoredValue != "API Key","Saved key was not read back after relaunch")
        let test=app.cells["DSAPI.TestConnection"].staticTexts.firstMatch
        if test.exists {
            XCTAssertTrue(reveal(app,test)); test.tap()
            let success=app.alerts["Connection succeeded"].firstMatch
            XCTAssertTrue(success.waitForExistence(timeout:60)); capture(app,"direct-saved-connection-test")
            success.buttons.firstMatch.tap()
        }
        app.buttons["DSAPI.Cancel"].tap()
        // The original settings sheet is underneath API settings.
        if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        app.terminate()
        let chat=openNativeApp()
        let input=try XCTUnwrap(chat.textViews.allElementsBoundByIndex.filter { $0.isHittable && $0.isEnabled }.max { $0.frame.maxY < $1.frame.maxY })
        enterPrompt("请把数字 173 和 286 相加，只回复结果。",into:input,in:chat)
        chat.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","Send","发送")).firstMatch.tap()
        let response=chat.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@","459","459")).firstMatch
        // The expected answer is absent from the question. Require both rendered
        // answer text and the completed native read-aloud control.
        let read=chat.buttons["DSAPI.ReadAloud"].firstMatch
        XCTAssertTrue(read.waitForExistence(timeout:90),"Direct API text request did not complete")
        XCTAssertTrue(response.waitForExistence(timeout:10))
        capture(chat,"direct-official-text-after-keychain-restart")
        try runNativeImage(prompt:"Name the color in this image. Respond in Chinese with the color name only.",expected:"红色")
    }
    func testNativeLiveAPIImage() throws {
        try runNativeImage(prompt:"Name the color in this image. Respond in Chinese with the color name only.",expected:"红色")
    }
    #endif
    private func runNativeImage(prompt:String,expected:String) throws {
        let app=openNativeApp()
        let input=try XCTUnwrap(app.textViews.allElementsBoundByIndex.filter { $0.isHittable && $0.isEnabled }.max { $0.frame.maxY < $1.frame.maxY })
        input.tap()
        dismissKeyboardHelp(app)
        input.typeText(prompt)
        dismissKeyboardHelp(app)
        // Set the synthetic image immediately before invoking the real native
        // paste action; typing and system clipboard inspection can race the
        // initial app fixture preparation on a cold simulator.
        UIPasteboard.general.image=UIGraphicsImageRenderer(size:CGSize(width:512,height:512)).image { context in
            context.cgContext.setFillColor(UIColor.red.cgColor); context.cgContext.fill(CGRect(x:0,y:0,width:512,height:512))
        }
        input.press(forDuration:1.2)
        if dismissKeyboardHelp(app) { input.press(forDuration:1.2) }
        let labels=["Paste","粘贴"]
        let pasteReady=XCTNSPredicateExpectation(predicate:NSPredicate { _, _ in
            labels.contains { app.menuItems[$0].firstMatch.exists || app.buttons[$0].firstMatch.exists }
        },object:app)
        _=XCTWaiter.wait(for:[pasteReady],timeout:5)
        let paste=labels.map { app.menuItems[$0].firstMatch }.first { $0.exists && $0.isHittable }
            ?? labels.map { app.buttons[$0].firstMatch }.first { $0.exists && $0.isHittable }
        if paste==nil { capture(app,"native-image-paste-menu-missing"); print("DSAPI_PASTE_MENU_BEGIN\n"+app.debugDescription+"\nDSAPI_PASTE_MENU_END") }
        XCTAssertNotNil(paste,"Original image-paste action is missing"); paste?.tap()
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        let allowPaste=springboard.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","Allow Paste","允许粘贴")).firstMatch
        if allowPaste.exists && allowPaste.isHittable { allowPaste.tap() }
        Thread.sleep(forTimeInterval:3)
        if allowPaste.exists && allowPaste.isHittable { allowPaste.tap() }
        dismissKeyboardHelp(app)
        capture(app,"native-image-upload")
        XCTAssertFalse(app.staticTexts["请求未携带验证信息"].firstMatch.exists)
        let send=app.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","Send","发送")).firstMatch
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate { _, _ in send.exists && send.isHittable && send.isEnabled },object:app)
        let canSend=XCTWaiter.wait(for:[ready],timeout:15) == .completed
        if !canSend { capture(app,"native-upload-not-ready"); print("DSAPI_IMAGE_UPLOAD_NOT_READY\n"+app.debugDescription) }
        XCTAssertTrue(canSend,"Original image upload did not finish and enable Send")
        send.tap()
        let reply=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@",expected,expected)).firstMatch
        let received=reply.waitForExistence(timeout:30)
        if !received { capture(app,"native-image-api-failure"); print("DSAPI_IMAGE_FAILURE_BEGIN\n"+app.debugDescription+"\nDSAPI_IMAGE_FAILURE_END") }
        XCTAssertTrue(received,"Native image did not reach the API as an image content part")
        capture(app,"native-image-api-reply")
    }

    @discardableResult private func reveal(_ app:XCUIApplication,_ element:XCUIElement,up:Bool=true) -> Bool {
        for _ in 0..<10 {
            let keyboard=app.keyboards.firstMatch
            let clearOfKeyboard = !keyboard.exists || element.frame.midY < keyboard.frame.minY-12
            if element.exists && element.isHittable && clearOfKeyboard { return true }
            let height=app.frame.height
            let bottom=keyboard.exists ? min(keyboard.frame.minY,height) : height
            let low=max(0.35,min(0.75,(bottom-30)/height)), high=max(0.18,low-0.30)
            let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:up ? low : high))
            let end=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:up ? high : low))
            start.press(forDuration:0.05,thenDragTo:end)
        }
        return element.exists && element.isHittable
    }

    private func enterPrompt(_ text:String,into input:XCUIElement,in app:XCUIApplication) {
        input.tap(); _ = dismissKeyboardHelp(app)
        input.typeText(text)
        let consumedByHelp=dismissKeyboardHelp(app)
        if consumedByHelp && ((input.value as? String) ?? "").isEmpty {
            input.tap(); input.typeText(text)
        }
        XCTAssertTrue(((input.value as? String) ?? "").contains(text),"The native composer did not retain the typed prompt")
    }

    @discardableResult private func dismissKeyboardHelp(_ app:XCUIApplication) -> Bool {
        let hint=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","sliding your finger")).firstMatch
        if hint.waitForExistence(timeout:2) {
            let next=app.buttons["Continue"].firstMatch
            if next.exists && next.isHittable { next.tap(); return true }
            else if app.staticTexts["Continue"].firstMatch.exists { app.staticTexts["Continue"].firstMatch.tap(); return true }
        }
        return false
    }

    private func openExistingTestChat() -> XCUIApplication {
        let app = openNativeApp()
        if !app.buttons.matching(identifier: "DSAPI.ReadAloud").allElementsBoundByIndex.contains(where: { $0.isHittable }) {
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
        let visibleRead = NSPredicate { _, _ in app.buttons.matching(identifier: "DSAPI.ReadAloud").allElementsBoundByIndex.contains(where: { $0.isHittable }) }
        expectation(for: visibleRead, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        let readAloud = try XCTUnwrap(app.buttons.matching(identifier: "DSAPI.ReadAloud").allElementsBoundByIndex.first(where: { $0.isHittable }), "Original read-aloud button is missing")
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
        let visibleRegenerate = NSPredicate { _, _ in app.buttons.matching(identifier: "Regenerate").allElementsBoundByIndex.contains { $0.isHittable } }
        expectation(for: visibleRegenerate, evaluatedWith: app)
        waitForExpectations(timeout: 30)
        let regenerate = try XCTUnwrap(app.buttons.matching(identifier: "Regenerate").allElementsBoundByIndex.first { $0.isHittable })
        capture(app, "before-native-regeneration")
        regenerate.tap()
        let stop = app.buttons["Stop"].firstMatch
        let generating = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in stop.exists && stop.isHittable }, object: app)
        let started = XCTWaiter.wait(for: [generating], timeout: 10) == .completed
        capture(app, "native-regeneration-started")
        print("DSAPI_REGENERATION_BEGIN\n" + String(app.debugDescription.suffix(24000)) + "\nDSAPI_REGENERATION_END")
        XCTAssertTrue(started, "Original regenerate action did not start a new stream")
        expectation(for: NSPredicate { _, _ in !app.buttons.matching(identifier: "Stop").allElementsBoundByIndex.contains { $0.isHittable } }, evaluatedWith: app)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "流式输出正常")).firstMatch.exists)
        capture(app, "native-regeneration-finished")
        #endif
    }

    func testNativeServiceSwitching() throws {
        #if DSAPI_MOCK_UI
        continueAfterFailure=false
        let app=XCUIApplication(bundleIdentifier: "com.deepseek.chat")
        app.terminate()
        app.launchArguments=["-DSAPIAdapter.probePresentAPI", "YES"]
        app.launch()
        var mode=app.switches["DSAPI.Enabled"].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 20), "API page did not become responsive")
        let initial=(mode.value as? String)=="1"
        for (index,target) in [!initial,initial,!initial,initial].enumerated() {
            mode=app.switches["DSAPI.Enabled"].firstMatch
            XCTAssertTrue(mode.exists && mode.isHittable)
            if ((mode.value as? String)=="1") != target { mode.tap() }
            XCTAssertEqual(mode.value as? String,target ? "1" : "0")
            app.buttons["DSAPI.Save"].tap()
            let alert=app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 10), "Mode save did not finish or UI froze")
            let ok=alert.buttons.firstMatch
            XCTAssertTrue(ok.exists && ok.isHittable); ok.tap()
            expectation(for: NSPredicate { _, _ in !mode.exists },evaluatedWith: app)
            waitForExpectations(timeout: 10)
            XCTAssertEqual(app.state,.runningForeground)
            app.terminate(); app.launch()
            mode=app.switches["DSAPI.Enabled"].firstMatch
            XCTAssertTrue(mode.waitForExistence(timeout: 20), "Relaunch froze after switching service")
            XCTAssertEqual(mode.value as? String,target ? "1" : "0", "Saved mode did not survive restart")
            capture(app,"service-switch-\(index)-\(target ? "api" : "original")")
            print("DSAPI_SWITCH_CYCLE=\(index),api=\(target),responsive=true")
        }
        app.buttons["DSAPI.Cancel"].tap()
        app.terminate()
        #endif
    }

    private func openOriginalSettings(_ app: XCUIApplication) -> Bool {
        if app.cells["DSAPI.APISettings"].firstMatch.exists { return true }
        let sidebar=app.buttons["open_sidebar"].firstMatch
        if sidebar.exists && sidebar.isHittable { sidebar.tap() }
        capture(app,"original-sidebar-account-retained")
        let avatar=app.images["sidebar/userAvatar"].firstMatch
        if avatar.exists && avatar.isHittable { avatar.tap() }
        else {
            let entry=app.buttons.matching(NSPredicate(format:"label == %@ OR label == %@ OR label == %@ OR label == %@","My Profile","Settings","个人信息","设置")).firstMatch
            if entry.exists && entry.isHittable { entry.tap() }
            else { app.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.94)).tap() }
        }
        let profile=app.buttons.matching(NSPredicate(format:"label == %@ OR label == %@ OR label == %@ OR label == %@","My Profile","Settings","设置","个人信息")).firstMatch
        if !app.cells["DSAPI.APISettings"].firstMatch.exists && profile.exists && profile.isHittable { profile.tap() }
        return app.staticTexts.matching(NSPredicate(format:"label == %@ OR label == %@ OR label == %@","Account settings","账号管理","帳號管理")).firstMatch.waitForExistence(timeout:10)
    }

    private func inspectSettings(_ app: XCUIApplication) -> Bool {
        guard openOriginalSettings(app) else {
            print("DSAPI_SETTINGS_FAILURE_BEGIN\n"+app.debugDescription+"\nDSAPI_SETTINGS_FAILURE_END")
            return false
        }
        let account=app.staticTexts.matching(NSPredicate(format:"label == %@ OR label == %@ OR label == %@","Account settings","账号管理","帳號管理")).firstMatch
        XCTAssertTrue(account.exists,"Original account settings must remain")
        for labels in [["Data controls","数据管理"],["Help & Feedback","帮助与反馈"],["Service agreement","服务协议"],["Log out","退出登录"]] {
            let row=app.staticTexts.matching(NSPredicate(format:"label == %@ OR label == %@",labels[0],labels[1])).firstMatch
            XCTAssertTrue(row.exists,"Original setting removed: \(labels[0])")
        }
        capture(app,"original-settings-account-retained")
        inspectNativePreferences(app)
        let api=app.cells["DSAPI.APISettings"].firstMatch
        for _ in 0..<8 {
            if api.exists && api.isHittable { break }
            app.tables.firstMatch.swipeUp()
        }
        XCTAssertFalse(app.navigationBars.buttons["DSAPI.APISettings"].firstMatch.exists)
        capture(app,"native-api-settings-row")
        XCTAssertTrue(api.exists && api.isHittable); api.tap()
        XCTAssertTrue(app.switches["DSAPI.Enabled"].firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(reveal(app,app.textFields["Base URL"]))
        XCTAssertTrue(reveal(app,app.secureTextFields["API Key"]))
        app.swipeUp()
        let usageOption=app.switches["DSAPI.RequestUsage"].firstMatch
        XCTAssertTrue(reveal(app,usageOption))
        if usageOption.exists && usageOption.isHittable {
            let previous=usageOption.value as? String; usageOption.tap()
            XCTAssertNotEqual(usageOption.value as? String,previous); usageOption.tap()
        }
        let usage=app.cells["DSAPI.Usage"].firstMatch
        _ = reveal(app,usage)
        XCTAssertTrue(usage.exists && usage.isHittable); usage.tap()
        capture(app,"api-usage-dashboard")
        let close=app.buttons["DSAPI.CloseUsage"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout:5)); close.tap()
        capture(app,"api-settings")
        return true
    }

    private func inspectNativePreferences(_ app: XCUIApplication) {
        let voice = app.cells.containing(.staticText,identifier:"Voice").firstMatch
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
        // The original voice-switched toast overlaps the Font size row and
        // consumes taps while visible. Wait for it instead of tapping through it.
        // This native toast is intentionally absent from some AX snapshots.
        Thread.sleep(forTimeInterval:4)
        let voiceToast=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","Voice switched"))
        expectation(for:NSPredicate { _, _ in voiceToast.count==0 },evaluatedWith:app)
        waitForExpectations(timeout:10)
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
                let preferences=XCUIApplication(bundleIdentifier: "com.apple.Preferences")
                XCTAssertTrue(preferences.wait(for: .runningForeground, timeout: 10), "Original language entry must open iOS app settings")
                capture(preferences, "original-system-language-entry")
                // Exercise the same iOS language preference at next launch. The
                // original app delegates language selection to system Settings.
                app.terminate()
                app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
                app.launch()
                XCTAssertTrue(openOriginalSettings(app),"Original account footer must still open settings after language switch")
                capture(app, "sidebar-after-language-change")
                XCTAssertTrue(app.staticTexts["语言"].firstMatch.waitForExistence(timeout: 5), "Original settings did not switch to Chinese")
                XCTAssertTrue(app.staticTexts["数据管理"].firstMatch.exists,"Original data setting must remain after language switch")
                XCTAssertTrue(app.staticTexts["账号管理"].firstMatch.exists,"Original account setting must remain after language switch")
                capture(app, "settings-after-language-change")
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
