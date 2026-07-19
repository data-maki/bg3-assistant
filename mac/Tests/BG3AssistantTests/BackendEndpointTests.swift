import Foundation
import XCTest
@testable import BG3HonorAssistant

final class BackendEndpointTests: XCTestCase {
    func testCanonicalLocalEndpointManagesTheBundledBackend() throws {
        let endpoint = try BackendEndpoint("http://127.0.0.1:8787")

        XCTAssertTrue(endpoint.managesLocalBackend)
        XCTAssertEqual(endpoint.url(path: "/api/chat").absoluteString, "http://127.0.0.1:8787/api/chat")
    }

    func testRemoteEndpointUsesHTTPSWithoutManagingALocalProcess() throws {
        let endpoint = try BackendEndpoint("https://assistant.example.com/")

        XCTAssertFalse(endpoint.managesLocalBackend)
        XCTAssertEqual(endpoint.baseURL.absoluteString, "https://assistant.example.com")
        XCTAssertEqual(endpoint.url(path: "map").absoluteString, "https://assistant.example.com/map")
    }

    func testEnvironmentOverridesPackagedEndpoint() throws {
        let endpoint = try BackendEndpoint.configured(
            environment: ["BG3_BACKEND_URL": "https://override.example.com"],
            infoDictionary: [BackendEndpoint.infoDictionaryKey: "https://packaged.example.com"]
        )

        XCTAssertEqual(endpoint.baseURL.absoluteString, "https://override.example.com")
    }

    func testPackagedEndpointIsUsedWithoutEnvironmentOverride() throws {
        let endpoint = try BackendEndpoint.configured(
            environment: [:],
            infoDictionary: [BackendEndpoint.infoDictionaryKey: "https://packaged.example.com"]
        )

        XCTAssertEqual(endpoint.baseURL.absoluteString, "https://packaged.example.com")
    }

    func testUnsafeOrAmbiguousEndpointsAreRejected() {
        let invalidEndpoints = [
            "http://api.example.com",
            "http://localhost:8787",
            "https://user:secret@api.example.com",
            "https://api.example.com/bg3",
            "https://api.example.com?token=secret",
            "https://api.example.com#fragment",
        ]

        for value in invalidEndpoints {
            XCTAssertThrowsError(try BackendEndpoint(value), value)
        }
    }

    func testRemoteBackendEnvironmentDropsProviderCredentials() throws {
        let remote = try BackendEndpoint("https://assistant.example.com")
        let environment = BackendProcessManager.childEnvironment(
            from: [
                "OPENROUTER_API_KEY": "must-not-reach-app-helper",
                "EXA_API_KEY": "must-not-reach-app-helper",
                "UNRELATED_SECRET": "must-not-reach-app-helper",
                "BG3_ASSISTANT_STATE_DIR": "/tmp/test-state",
            ],
            stateDatabasePath: "/tmp/test-state/state.sqlite3",
            upstreamBackendEndpoint: remote,
            companionControlToken: "ephemeral-control-token"
        )

        XCTAssertNil(environment["OPENROUTER_API_KEY"])
        XCTAssertNil(environment["EXA_API_KEY"])
        XCTAssertNil(environment["UNRELATED_SECRET"])
        XCTAssertEqual(environment["BG3_UPSTREAM_BACKEND_URL"], "https://assistant.example.com")
        XCTAssertEqual(environment["BG3_STATE_DB_PATH"], "/tmp/test-state/state.sqlite3")
        XCTAssertEqual(environment["RUNS_DIR"], "/tmp/test-state/backend-runs")
        XCTAssertEqual(environment["BG3_BACKEND_MODE"], "local")
        XCTAssertEqual(environment["BG3_COMPANION_CONTROL_TOKEN"], "ephemeral-control-token")
    }
}
