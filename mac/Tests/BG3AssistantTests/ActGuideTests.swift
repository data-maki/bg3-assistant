import Foundation
import XCTest
@testable import BG3HonorAssistant

final class ActGuideTests: XCTestCase {
    func testActMapHandoffsKeepOnlyActOneLocal() {
        func guide(act: Int, local: Bool, url: String) -> ActGuideSummary {
            ActGuideSummary(
                act: act,
                title: "Act \(act)",
                routeAvailable: true,
                localMapAvailable: local,
                mapName: "Map",
                mapUrl: url,
                equipmentFile: "gear.tsv",
                coordinateSystem: "BG3 XY",
                coordinateNote: "",
                equipmentCount: 0
            )
        }

        XCTAssertEqual(guide(act: 1, local: true, url: "https://example.com/one").mapHandoff, .local)
        XCTAssertEqual(guide(act: 2, local: false, url: "https://example.com/two").mapHandoff, .external(URL(string: "https://example.com/two")!))
        XCTAssertEqual(guide(act: 3, local: false, url: "https://example.com/three").mapHandoff, .external(URL(string: "https://example.com/three")!))
    }
}
