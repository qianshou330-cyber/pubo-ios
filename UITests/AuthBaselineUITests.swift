import XCTest
final class AuthBaselineUITests: XCTestCase {
    private func capture(_ app: XCUIApplication,_ name: String){Thread.sleep(forTimeInterval:0.5);let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    func testUnmodified105AuthBothThemes(){
        for dark in [false,true]{
            let app=XCUIApplication();app.launchArguments=["--ui-testing","--logged-out"]+(dark ? ["--dark"]:[]);app.launch()
            let theme=dark ? "dark":"light"
            XCTAssertTrue(app.buttons["auth.openLogin"].waitForExistence(timeout:15));capture(app,"build105-welcome-"+theme)
            app.buttons["auth.openLogin"].tap();XCTAssertTrue(app.textFields["auth.username"].waitForExistence(timeout:5));capture(app,"build105-username-"+theme)
            app.textFields["auth.username"].tap();app.textFields["auth.username"].typeText("fixture");app.buttons["auth.loginContinue"].tap()
            XCTAssertTrue(app.secureTextFields["auth.password"].waitForExistence(timeout:5));capture(app,"build105-password-"+theme)
            app.buttons["auth.close"].tap();app.buttons["auth.openRegister"].tap();capture(app,"build105-rules-"+theme)
            app.switches["auth.agreePolicy"].tap();let notes=app.switches["auth.agreeNotes"];for _ in 0..<5 where !notes.isHittable{app.swipeUp()};notes.tap()
            let next=app.buttons["auth.registrationContinue"];for _ in 0..<5 where !next.isHittable{app.swipeUp()};next.tap()
            XCTAssertTrue(app.textFields["auth.phone"].waitForExistence(timeout:5));capture(app,"build105-signup-"+theme);app.terminate()
        }
    }
}

