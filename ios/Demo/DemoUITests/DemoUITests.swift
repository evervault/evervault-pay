//
//  DemoUITests.swift
//  DemoUITests
//
//  Created by Jake Grogan on 12/06/2025.
//

import XCTest

final class DemoUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

//    func testCheckoutOneOff() {
//        let app = XCUIApplication()
//        app.activate()
//        app/*@START_MENU_TOKEN@*/.images["home"]/*[[".buttons",".images[\"home\"]",".images[\"house.fill\"]",".images.firstMatch"],[[[-1,2],[-1,1],[-1,3],[-1,0,1]],[[-1,2],[-1,1]]],[1]]@END_MENU_TOKEN@*/.tap()
//        app/*@START_MENU_TOKEN@*/.buttons["Check out with Apple Pay"]/*[[".otherElements.buttons[\"Check out with Apple Pay\"]",".buttons[\"Check out with Apple Pay\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.tap()
//        XCUIDevice.shared.press(.home)
//        
//        let springboardApp = XCUIApplication(bundleIdentifier: "com.apple.springboard")
//        springboardApp/*@START_MENU_TOKEN@*/.buttons["Pay with Passcode"]/*[[".otherElements",".buttons[\"Pay with Passcode\"]",".buttons[\"footer\"]"],[[[-1,2],[-1,1],[-1,0,1]],[[-1,2],[-1,1]]],[1]]@END_MENU_TOKEN@*/.tap()
//    }
}
