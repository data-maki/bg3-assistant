import Foundation
import XCTest
@testable import BG3HonorAssistant

final class ActGuideTests: XCTestCase {
    private func decode(_ json: String) throws -> RoutePayload {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RoutePayload.self, from: Data(json.utf8))
    }

    func testActThreeGuideDecodesNullableMapProvenance() throws {
        let payload = try decode(#"""
        {
          "guideVersion": "test",
          "act": 3,
          "routeAvailable": true,
          "checkpoints": [{
            "id": "act3-test",
            "route_order": 1,
            "name": "Test",
            "area": "Lower City",
            "region": "Baldur's Gate",
            "x": null,
            "y": null,
            "minimum_level": 12,
            "importance": "major",
            "danger": "extreme",
            "enemies": "",
            "advice": "Prepare",
            "legendary_action": null,
            "failure_conditions": [],
            "preparation": [],
            "completion_checks": [],
            "irreversible_warnings": [],
            "prerequisites": [],
            "notes": [],
            "honor_decisions": [],
            "source": {"sheet": "BG3 Wiki", "row": null, "url": "https://bg3.wiki"}
          }],
          "builds": [],
          "walkthrough": [],
          "timedEvents": [{
            "id": "deadline",
            "name": "Deadline",
            "kind": "immediate",
            "trigger": "Start",
            "deadline": "Now",
            "consequence": "Lost",
            "severity": "critical",
            "source": "https://bg3.wiki"
          }],
          "acts": []
        }
        """#)

        XCTAssertEqual(payload.act, 3)
        XCTAssertTrue(payload.routeAvailable)
        XCTAssertNil(payload.checkpoints[0].x)
        XCTAssertNil(payload.checkpoints[0].y)
        XCTAssertNil(payload.checkpoints[0].source.row)
        XCTAssertEqual(payload.timedEvents.map(\.id), ["deadline"])
    }

    func testUnavailableActGuideDecodesAsAnEmptyGuide() throws {
        let payload = try decode(#"""
        {
          "guideVersion": "test",
          "act": 2,
          "routeAvailable": false,
          "checkpoints": [],
          "builds": [],
          "walkthrough": [],
          "timedEvents": [],
          "acts": []
        }
        """#)

        XCTAssertEqual(payload.act, 2)
        XCTAssertFalse(payload.routeAvailable)
        XCTAssertTrue(payload.checkpoints.isEmpty)
        XCTAssertTrue(payload.walkthrough.isEmpty)
    }

    func testBackendPathsAreActScoped() {
        XCTAssertEqual(BackendClient.guidePath(for: 3), "api/acts/3/guide")
        XCTAssertEqual(BackendClient.readinessPath(for: 3), "api/acts/3/readiness")
    }

    func testReadinessRequestEncodesNewStateAsSnakeCase() throws {
        let request = ReadinessRequest(
            checkpointId: "act3-orin",
            party: [],
            completedCheckpointIds: ["done"],
            skippedCheckpointIds: ["skipped"],
            checkedPreparation: ["prepared"],
            walkthroughStatuses: ["step": "completed"],
            walkthroughOutcomes: ["step": "outcome"]
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])

        XCTAssertEqual(payload["skipped_checkpoint_ids"] as? [String], ["skipped"])
        XCTAssertEqual(payload["checked_preparation"] as? [String], ["prepared"])
        XCTAssertEqual(payload["walkthrough_statuses"] as? [String: String], ["step": "completed"])
        XCTAssertEqual(payload["walkthrough_outcomes"] as? [String: String], ["step": "outcome"])
    }

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
