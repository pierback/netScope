import Foundation
import Testing
@testable import NetScopeCore

@Test func baselineLearnsAggregateAveragesWithoutRawSamples() {
    let now = Date(timeIntervalSince1970: 1_000)
    var baseline = TrafficBaseline(maximumAgeSeconds: 3_600, maximumApps: 10)

    baseline.record(apps: [app("codex", down: 40_000, up: 80_000)], at: now)
    baseline.record(apps: [app("codex", down: 80_000, up: 160_000)], at: now.addingTimeInterval(60))

    let record = baseline.recordsByAppName["codex"]

    #expect(record?.sampleCount == 2)
    #expect(record?.averageBytesInPerSecond == 60_000)
    #expect(record?.averageBytesOutPerSecond == 120_000)
    #expect(record?.peakBytesInPerSecond == 80_000)
    #expect(record?.peakBytesOutPerSecond == 160_000)
}

@Test func baselineIgnoresLowVolumeApps() {
    let now = Date(timeIntervalSince1970: 1_500)
    var baseline = TrafficBaseline(maximumAgeSeconds: 3_600, maximumApps: 10)

    let changed = baseline.record(apps: [app("helper", down: 4_000, up: 4_000)], at: now)

    #expect(changed == false)
    #expect(baseline.recordsByAppName.isEmpty)
}

@Test func baselineRecordReturnsFalseWhenNoAggregateChanged() {
    let now = Date(timeIntervalSince1970: 1_700)
    var baseline = TrafficBaseline(maximumAgeSeconds: 3_600, maximumApps: 10)

    let changed = baseline.record(apps: [app("helper", down: 4_000, up: 4_000)], at: now)

    #expect(changed == false)
    #expect(baseline.recordsByAppName.isEmpty)
}

@Test func baselineDoesNotCompareUntilEnoughSamplesExist() {
    let now = Date(timeIntervalSince1970: 2_000)
    var baseline = TrafficBaseline(maximumAgeSeconds: 3_600, maximumApps: 10)

    baseline.record(apps: [app("codex", down: 40_000, up: 40_000)], at: now)

    let assessment = baseline.assess(apps: [app("codex", down: 200_000, up: 200_000)], at: now.addingTimeInterval(60))

    #expect(assessment.state == .learning)
    #expect(assessment.findings.isEmpty)
}

@Test func baselineFlagsAboveUsualTraffic() {
    let now = Date(timeIntervalSince1970: 3_000)
    var baseline = TrafficBaseline(maximumAgeSeconds: 3_600, maximumApps: 10)

    for index in 0..<3 {
        baseline.record(apps: [app("codex", down: 40_000, up: 40_000)], at: now.addingTimeInterval(Double(index)))
    }

    let assessment = baseline.assess(apps: [app("codex", down: 200_000, up: 50_000)], at: now.addingTimeInterval(60))

    #expect(assessment.state == .changed)
    #expect(assessment.findings.count == 1)

    if case let .aboveUsual(appName, multiplier, _, _) = assessment.findings[0] {
        #expect(appName == "codex")
        #expect(multiplier >= 3)
    } else {
        Issue.record("Expected above-usual baseline finding")
    }
}

@Test func baselineFlagsNewActiveApps() {
    let now = Date(timeIntervalSince1970: 4_000)
    var baseline = TrafficBaseline(maximumAgeSeconds: 3_600, maximumApps: 10)

    for index in 0..<3 {
        baseline.record(apps: [app("Safari", down: 40_000, up: 40_000)], at: now.addingTimeInterval(Double(index)))
    }

    let assessment = baseline.assess(apps: [app("Dropbox", down: 120_000, up: 80_000)], at: now.addingTimeInterval(60))

    #expect(assessment.state == .changed)

    if case let .newActiveApp(appName, _) = assessment.findings[0] {
        #expect(appName == "Dropbox")
    } else {
        Issue.record("Expected new-active baseline finding")
    }
}

@Test func baselinePrunesByAgeAndAppLimit() {
    let now = Date(timeIntervalSince1970: 5_000)
    var baseline = TrafficBaseline(maximumAgeSeconds: 120, maximumApps: 2)

    baseline.record(apps: [app("Old", down: 40_000, up: 40_000)], at: now.addingTimeInterval(-500))
    baseline.record(apps: [app("A", down: 40_000, up: 40_000)], at: now)
    baseline.record(apps: [app("B", down: 40_000, up: 40_000)], at: now.addingTimeInterval(1))
    baseline.record(apps: [app("C", down: 40_000, up: 40_000)], at: now.addingTimeInterval(2))
    baseline.prune(now: now.addingTimeInterval(2))

    #expect(baseline.recordsByAppName["old"] == nil)
    #expect(baseline.recordsByAppName.count == 2)
    #expect(baseline.recordsByAppName["b"] != nil)
    #expect(baseline.recordsByAppName["c"] != nil)
}

@Test func localBaselineStoreLoadsSavesAndClearsAggregateFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("netscope-baseline-tests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("baseline.json")
    let store = try LocalTrafficBaselineStore(fileURL: fileURL)
    let now = Date()
    var baseline = TrafficBaseline(maximumAgeSeconds: 3_600, maximumApps: 10)
    baseline.record(apps: [app("codex", down: 40_000, up: 40_000)], at: now)

    try store.save(baseline)
    let loaded = try store.load()

    #expect(loaded.recordsByAppName["codex"]?.sampleCount == 1)
    #expect(FileManager.default.fileExists(atPath: fileURL.path))

    try store.clear()

    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
}

private func app(_ name: String, down: Int, up: Int) -> AppTraffic {
    AppTraffic(
        displayName: name,
        pid: 42,
        bytesInPerSecond: down,
        bytesOutPerSecond: up,
        retransmitsPerSecond: 0
    )
}
