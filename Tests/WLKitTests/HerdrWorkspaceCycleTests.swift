import XCTest
@testable import WLKit

final class HerdrWorkspaceCycleTests: XCTestCase {

    func testAdvancesToTheNextWorkspaceByNumber() {
        let workspaces = [
            HerdrWorkspace(workspaceID: "w1", number: 1, focused: true),
            HerdrWorkspace(workspaceID: "w2", number: 2),
            HerdrWorkspace(workspaceID: "w3", number: 3),
        ]
        XCTAssertEqual(HerdrClient.nextWorkspace(in: workspaces)?.workspaceID, "w2")
    }

    func testWrapsFromTheLastWorkspaceToTheFirst() {
        let workspaces = [
            HerdrWorkspace(workspaceID: "w1", number: 1),
            HerdrWorkspace(workspaceID: "w2", number: 2, focused: true),
        ]
        XCTAssertEqual(HerdrClient.nextWorkspace(in: workspaces)?.workspaceID, "w1")
    }

    func testCyclesInNumberOrderNotListOrder() {
        let workspaces = [
            HerdrWorkspace(workspaceID: "w3", number: 3),
            HerdrWorkspace(workspaceID: "w1", number: 1, focused: true),
            HerdrWorkspace(workspaceID: "w2", number: 2),
        ]
        XCTAssertEqual(HerdrClient.nextWorkspace(in: workspaces)?.workspaceID, "w2")
    }

    func testSingleWorkspaceHasNowhereToGo() {
        XCTAssertNil(HerdrClient.nextWorkspace(in: [
            HerdrWorkspace(workspaceID: "w1", number: 1, focused: true)
        ]))
    }

    func testNoFocusedWorkspaceDoesNothing() {
        let workspaces = [
            HerdrWorkspace(workspaceID: "w1", number: 1),
            HerdrWorkspace(workspaceID: "w2", number: 2),
        ]
        XCTAssertNil(HerdrClient.nextWorkspace(in: workspaces))
    }

    func testPreviousWorkspaceGoesToTheEarlierNumber() {
        let workspaces = [
            HerdrWorkspace(workspaceID: "w1", number: 1),
            HerdrWorkspace(workspaceID: "w2", number: 2, focused: true),
            HerdrWorkspace(workspaceID: "w3", number: 3),
        ]
        XCTAssertEqual(HerdrClient.previousWorkspace(in: workspaces)?.workspaceID, "w1")
    }

    func testPreviousWorkspaceWrapsFromTheFirstToTheLast() {
        let workspaces = [
            HerdrWorkspace(workspaceID: "w1", number: 1, focused: true),
            HerdrWorkspace(workspaceID: "w2", number: 2),
            HerdrWorkspace(workspaceID: "w3", number: 3),
        ]
        XCTAssertEqual(HerdrClient.previousWorkspace(in: workspaces)?.workspaceID, "w3")
    }

    func testPreviousWorkspaceSingleHasNowhereToGo() {
        XCTAssertNil(HerdrClient.previousWorkspace(in: [
            HerdrWorkspace(workspaceID: "w1", number: 1, focused: true)
        ]))
    }

    func testPreviousWorkspaceNoFocusedDoesNothing() {
        let workspaces = [
            HerdrWorkspace(workspaceID: "w1", number: 1),
            HerdrWorkspace(workspaceID: "w2", number: 2),
        ]
        XCTAssertNil(HerdrClient.previousWorkspace(in: workspaces))
    }
}
