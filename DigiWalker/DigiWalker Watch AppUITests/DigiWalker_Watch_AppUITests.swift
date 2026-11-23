//
//  DigiWalker_Watch_AppUITests.swift
//  DigiWalker Watch AppUITests
//
//  Created by 박태양M1 on 11/22/26.
//

import XCTest

final class DigiWalker_Watch_AppUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testPartnerAndHealthEntryPoint() throws {
        let app = XCUIApplication()
        app.launch()
        let connect = app.buttons["건강 데이터 연결"]
        let refresh = app.buttons["활동량 갱신"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5) || refresh.exists)
        XCTAssertTrue(app.staticTexts["partnerGrowth"].exists)
        if connect.exists { connect.tap() } else { refresh.tap() }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "건강 데이터 연결 화면"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
