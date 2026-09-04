import XCTest
@testable import WLKit

final class ConfigFileWatcherTests: XCTestCase {

    func testWriteFiresOnceAfterDebounce() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("config-watch-\(UUID().uuidString)", isDirectory: true)
        let path = dir.appendingPathComponent("config.json").path

        let fired = expectation(description: "config changed")
        fired.expectedFulfillmentCount = 1

        let watcher = ConfigFileWatcher(path: path, debounce: 0.25) {
            fired.fulfill()
        }
        watcher.start()
        addTeardownBlock { watcher.stop() }

        try "one".write(toFile: path, atomically: true, encoding: .utf8)
        try "two".write(toFile: path, atomically: true, encoding: .utf8)

        wait(for: [fired], timeout: 2)
    }
}
