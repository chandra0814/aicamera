import XCTest
@testable import LensPilotCore

final class AiBenchmarkTests: XCTestCase {
    func testGuidanceBenchmarksStaySinglePhoneAndActionable() throws {
        let suite: BenchmarkSuite = try decodeRepositoryJSON("tests/benchmarks/ai-guidance-benchmarks.json")
        let deviceCapability: DeviceCapability = try decodeRepositoryJSON("tests/fixtures/iphone-device-capability.json")
        let aiCore = LensPilotAiCore()

        XCTAssertEqual(suite.cases.count, 6)

        for benchmark in suite.cases {
            let result = aiCore.run(
                prompt: benchmark.prompt,
                sceneState: benchmark.sceneState,
                deviceCapability: deviceCapability
            )

            XCTAssertTrue(result.shotSpec.constraints.singlePhoneOnly, "\(benchmark.id): must stay single-phone only")
            XCTAssertFalse(result.shotSpec.constraints.cloudAllowed, "\(benchmark.id): should not require cloud guidance")
            XCTAssertFalse(result.shotSpec.constraints.generativeEditsAllowed, "\(benchmark.id): should not require generative edits")
            XCTAssertFalse(result.shotSpec.subject.identityRecognitionAllowed, "\(benchmark.id): identity recognition must stay disabled")
            XCTAssertEqual(result.shotSpec.domain, benchmark.expected.domain, "\(benchmark.id): domain mismatch")
            XCTAssertEqual(result.shotPlan.cameraControls.recommendedLens, benchmark.expected.recommendedLens, "\(benchmark.id): lens mismatch")

            if let targetExposureBias = benchmark.expected.targetExposureBias {
                XCTAssertEqual(
                    result.shotPlan.cameraControls.targetExposureBias ?? 0,
                    targetExposureBias,
                    accuracy: 0.0001,
                    "\(benchmark.id): exposure bias mismatch"
                )
            }

            if let expectedGuidance = benchmark.expected.guidance {
                let guidanceAction = try XCTUnwrap(result.guidanceAction, "\(benchmark.id): expected guidance action")
                XCTAssertEqual(guidanceAction.actor, expectedGuidance.actor, "\(benchmark.id): guidance actor mismatch")
                XCTAssertEqual(guidanceAction.action, expectedGuidance.action, "\(benchmark.id): guidance action mismatch")
                XCTAssertEqual(guidanceAction.reason, expectedGuidance.reason, "\(benchmark.id): guidance reason mismatch")

                if let safetyQualifier = expectedGuidance.safetyQualifier {
                    XCTAssertEqual(guidanceAction.safetyQualifier, Optional(safetyQualifier), "\(benchmark.id): safety qualifier mismatch")
                }
            }

            assertMinimum(benchmark.expected.minOverallTargetMatch, result.targetMatch.overall, "overall Target Match", benchmark.id)
            assertMaximum(benchmark.expected.maxBackgroundScore, result.targetMatch.background, "background score", benchmark.id)
            assertMaximum(benchmark.expected.maxHorizonScore, result.targetMatch.horizon, "horizon score", benchmark.id)
            assertMaximum(benchmark.expected.maxExposureScore, result.targetMatch.exposure, "exposure score", benchmark.id)
            assertMaximum(benchmark.expected.maxSharpnessProbability, result.targetMatch.sharpnessProbability, "sharpness probability", benchmark.id)
            assertMaximum(benchmark.expected.maxLightingScore, result.targetMatch.lighting, "lighting score", benchmark.id)
        }
    }

    private func assertMinimum(_ expected: Double?, _ actual: Double, _ label: String, _ benchmarkId: String) {
        guard let expected else { return }
        XCTAssertGreaterThanOrEqual(actual, expected, "\(benchmarkId): expected \(label) >= \(expected), got \(actual)")
    }

    private func assertMaximum(_ expected: Double?, _ actual: Double, _ label: String, _ benchmarkId: String) {
        guard let expected else { return }
        XCTAssertLessThanOrEqual(actual, expected, "\(benchmarkId): expected \(label) <= \(expected), got \(actual)")
    }
}

private struct BenchmarkSuite: Decodable {
    let version: String
    let cases: [BenchmarkCase]
}

private struct BenchmarkCase: Decodable {
    let id: String
    let prompt: String
    let sceneState: SceneState
    let expected: BenchmarkExpectation
}

private struct BenchmarkExpectation: Decodable {
    let domain: CaptureDomain
    let recommendedLens: String
    let targetExposureBias: Double?
    let guidance: ExpectedGuidance?
    let minOverallTargetMatch: Double?
    let maxBackgroundScore: Double?
    let maxHorizonScore: Double?
    let maxExposureScore: Double?
    let maxSharpnessProbability: Double?
    let maxLightingScore: Double?
}

private struct ExpectedGuidance: Decodable {
    let actor: GuidanceAction.Actor
    let action: GuidanceAction.Action
    let reason: GuidanceAction.Reason
    let safetyQualifier: GuidanceAction.SafetyQualifier?
}

private func decodeRepositoryJSON<T: Decodable>(_ relativePath: String) throws -> T {
    let url = try repositoryFileURL(relativePath)
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(T.self, from: data)
}

private func repositoryFileURL(_ relativePath: String) throws -> URL {
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    let candidates = [
        currentDirectory.appendingPathComponent(relativePath),
        currentDirectory.appendingPathComponent("../../\(relativePath)"),
        sourceRoot.appendingPathComponent(relativePath)
    ]

    if let existing = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
        return existing
    }

    throw BenchmarkFixtureError.missingFile(relativePath)
}

private enum BenchmarkFixtureError: Error {
    case missingFile(String)
}
