import XCTest

// UI tests for the signed-out screens: Welcome, About, Sign Up and Log In.
// Nothing here signs in, creates an account or sends a request, so the
// simulator never needs a network. Elements are found by accessibility
// identifier, never by visible text, apart from the two segments of the
// Phone/Email picker, which can't carry their own identifier.
@MainActor
final class BloomUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        app = nil
    }

    // MARK: Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func textField(_ identifier: String) -> XCUIElement {
        app.textFields[identifier]
    }

    private func secureField(_ identifier: String) -> XCUIElement {
        app.secureTextFields[identifier]
    }

    @discardableResult
    private func waitFor(_ element: XCUIElement, _ description: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(description) should appear", file: file, line: line)
        return element
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func type(_ text: String, into field: XCUIElement) {
        field.tap()
        field.typeText(text)
    }

    // Swipes a list up until the element exists, since rows far down a
    // List aren't created until they scroll into view.
    private func scrollUntilExists(_ target: XCUIElement, in container: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !target.exists && swipes < maxSwipes {
            container.swipeUp()
            swipes += 1
        }
    }

    private func openSignUp() {
        waitFor(element("welcome.signUp"), "Sign Up button").tap()
        waitFor(element("signUp.submit"), "Sign Up submit button")
    }

    private func openLogIn() {
        waitFor(element("welcome.logIn"), "Log In button").tap()
        waitFor(element("logIn.submit"), "Log In submit button")
    }

    private func choose(_ method: String, in picker: String) {
        let segment = app.segmentedControls[picker].buttons[method]
        waitFor(segment, "\(method) segment").tap()
    }

    // MARK: Welcome

    func testWelcomeShowsSignUpLogInAndAbout() {
        waitFor(element("welcome.signUp"), "Sign Up button")
        waitFor(element("welcome.logIn"), "Log In button")
        waitFor(element("welcome.about"), "About button")
        XCTAssertTrue(element("welcome.signUp").isEnabled)
        XCTAssertTrue(element("welcome.logIn").isEnabled)
        attachScreenshot("Welcome screen")
    }

    // MARK: About

    func testAboutShowsDeveloperDetailsAndTMDBAttribution() {
        waitFor(element("welcome.about"), "About button").tap()
        let list = waitFor(element("about.list"), "About list")
        attachScreenshot("About opened from Welcome")

        let name = element("about.name")
        scrollUntilExists(name, in: list)
        waitFor(name, "Developer name row")
        XCTAssertTrue(name.label.contains("Emily Du"), "Name row reads \(name.label)")

        let studentID = element("about.studentID")
        scrollUntilExists(studentID, in: list)
        waitFor(studentID, "Student ID row")
        XCTAssertTrue(studentID.label.contains("34942238"), "Student ID row reads \(studentID.label)")
        attachScreenshot("About developer details")

        let tmdb = element("about.tmdb")
        scrollUntilExists(tmdb, in: list)
        waitFor(tmdb, "TMDB attribution")
        XCTAssertEqual(
            tmdb.label,
            "This product uses the TMDB API but is not endorsed or certified by TMDB."
        )
        attachScreenshot("About TMDB attribution")
    }

    func testAboutDoneClosesTheSheet() {
        waitFor(element("welcome.about"), "About button").tap()
        waitFor(element("about.list"), "About list")
        attachScreenshot("About before closing")

        waitFor(element("about.close"), "Done button").tap()

        waitFor(element("welcome.about"), "Welcome About button after closing")
        XCTAssertFalse(element("about.list").exists, "About should be closed")
        attachScreenshot("Welcome after closing About")
    }

    // MARK: Sign Up

    func testSignUpSubmitIsDisabledWithEmptyFields() {
        openSignUp()
        XCTAssertFalse(element("signUp.submit").isEnabled, "Submit should be disabled with empty fields")
        XCTAssertFalse(element("signUp.usernameError").exists, "An untouched form shows no error")
        attachScreenshot("Sign Up with empty fields")
    }

    func testSignUpShortUsernameShowsErrorAndValidUsernameClearsIt() {
        openSignUp()
        let username = waitFor(textField("signUp.username"), "Username field")

        type("ab", into: username)
        let error = waitFor(element("signUp.usernameError"), "Username error")
        XCTAssertEqual(error.label, "Username must be 3 to 30 characters.")
        XCTAssertFalse(element("signUp.submit").isEnabled)
        attachScreenshot("Sign Up too short username")

        username.typeText("c")
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: element("signUp.usernameError"))
        waitForExpectations(timeout: 5)
        attachScreenshot("Sign Up valid username clears the error")
    }

    func testSignUpInvalidCharactersShowTheCharactersError() {
        openSignUp()
        type("bad name", into: waitFor(textField("signUp.username"), "Username field"))
        let error = waitFor(element("signUp.usernameError"), "Username error")
        XCTAssertEqual(error.label, "Username can only contain letters, numbers, underscore and dot.")
        attachScreenshot("Sign Up invalid username characters")
    }

    func testSignUpSubmitEnablesWithValidNamesAndUsername() {
        openSignUp()
        type("Emily", into: waitFor(textField("signUp.displayName"), "Display name field"))
        type("emily_du", into: textField("signUp.username"))
        XCTAssertTrue(element("signUp.submit").isEnabled, "Submit should enable with a valid name and username")
        attachScreenshot("Sign Up ready to submit (not tapped)")
    }

    func testSignUpSwitchesBetweenPhoneAndEmailFields() {
        openSignUp()

        // Phone is the default.
        waitFor(textField("signUp.phone"), "Phone field")
        XCTAssertFalse(textField("signUp.email").exists)
        XCTAssertFalse(secureField("signUp.password").exists)
        XCTAssertEqual(element("signUp.submit").label, "Send Code")
        attachScreenshot("Sign Up Phone fields")

        choose("Email", in: "signUp.method")
        waitFor(textField("signUp.email"), "Email field")
        waitFor(secureField("signUp.password"), "Password field")
        XCTAssertFalse(textField("signUp.phone").exists)
        XCTAssertEqual(element("signUp.submit").label, "Sign Up")
        attachScreenshot("Sign Up Email fields")

        choose("Phone", in: "signUp.method")
        waitFor(textField("signUp.phone"), "Phone field again")
        XCTAssertFalse(textField("signUp.email").exists)
        attachScreenshot("Sign Up back to Phone fields")
    }

    func testSignUpCancelClosesTheSheet() {
        openSignUp()
        element("signUp.cancel").tap()
        waitFor(element("welcome.signUp"), "Welcome Sign Up button after cancelling")
        XCTAssertFalse(element("signUp.submit").exists)
    }

    // MARK: Log In

    func testLogInPhoneAndEmailTabsShowTheRightFields() {
        openLogIn()

        waitFor(textField("logIn.phone"), "Phone field")
        XCTAssertFalse(textField("logIn.email").exists)
        XCTAssertFalse(secureField("logIn.password").exists)
        attachScreenshot("Log In Phone fields")

        choose("Email", in: "logIn.method")
        waitFor(textField("logIn.email"), "Email field")
        waitFor(secureField("logIn.password"), "Password field")
        XCTAssertFalse(textField("logIn.phone").exists)
        attachScreenshot("Log In Email fields")
    }

    // The brief says the submit button is disabled when empty. LogInView
    // currently only disables it while submitting, so this test is expected
    // to fail until the app is changed (see the report).
    func testLogInSubmitIsDisabledWhenEmpty() {
        openLogIn()
        attachScreenshot("Log In with empty phone field")
        XCTAssertFalse(element("logIn.submit").isEnabled, "Phone submit should be disabled when empty")

        choose("Email", in: "logIn.method")
        waitFor(textField("logIn.email"), "Email field")
        attachScreenshot("Log In with empty email fields")
        XCTAssertFalse(element("logIn.submit").isEnabled, "Email submit should be disabled when empty")
    }

    func testLogInCancelClosesTheSheet() {
        openLogIn()
        element("logIn.cancel").tap()
        waitFor(element("welcome.logIn"), "Welcome Log In button after cancelling")
        XCTAssertFalse(element("logIn.submit").exists)
    }

    // MARK: Rotation

    func testRotatingKeepsTypedTextAndTheSignUpSheet() {
        openSignUp()
        type("Emily", into: waitFor(textField("signUp.displayName"), "Display name field"))
        type("emily_du", into: textField("signUp.username"))
        attachScreenshot("Sign Up portrait before rotating")

        XCUIDevice.shared.orientation = .landscapeLeft
        waitFor(element("signUp.submit"), "Sign Up sheet in landscape")
        XCTAssertEqual(textField("signUp.displayName").value as? String, "Emily")
        XCTAssertEqual(textField("signUp.username").value as? String, "emily_du")
        attachScreenshot("Sign Up landscape")

        XCUIDevice.shared.orientation = .portrait
        waitFor(element("signUp.submit"), "Sign Up sheet back in portrait")
        XCTAssertEqual(textField("signUp.displayName").value as? String, "Emily")
        XCTAssertEqual(textField("signUp.username").value as? String, "emily_du")
        XCTAssertTrue(element("signUp.submit").isEnabled)
        attachScreenshot("Sign Up portrait after rotating")
    }

    func testRotatingKeepsTypedTextOnTheLogInSheet() {
        openLogIn()
        choose("Email", in: "logIn.method")
        type("someone@example.com", into: waitFor(textField("logIn.email"), "Email field"))
        attachScreenshot("Log In portrait before rotating")

        XCUIDevice.shared.orientation = .landscapeRight
        waitFor(element("logIn.submit"), "Log In sheet in landscape")
        XCTAssertEqual(textField("logIn.email").value as? String, "someone@example.com")
        attachScreenshot("Log In landscape")

        XCUIDevice.shared.orientation = .portrait
        waitFor(element("logIn.submit"), "Log In sheet back in portrait")
        XCTAssertEqual(textField("logIn.email").value as? String, "someone@example.com")
        attachScreenshot("Log In portrait after rotating")
    }
}
