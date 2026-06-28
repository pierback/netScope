import Foundation
import NetScopeCore

@main
struct NetScopeCLI {
    static func main() {
        do {
            let snapshot = try SnapshotService().capture()
            let diagnosis = snapshot.diagnosis

            print("NetScope")
            print("Mode: CLI on-demand full check")
            print("Diagnosis: \(diagnosis.title)")
            print("Confidence: \(diagnosis.confidence.rawValue)")
            print("")
            print("Evidence:")
            for reason in diagnosis.reasons {
                print("- \(reason)")
            }

            if !diagnosis.topApps.isEmpty {
                print("")
                print("Top network apps now:")
                for (index, app) in diagnosis.topApps.enumerated() {
                    let pid = app.pid.map { " pid \($0)" } ?? ""
                    print("\(index + 1). \(app.displayName)\(pid): \(TrafficFormatting.appTraffic(app))")
                }
            }
        } catch {
            fputs("NetScope failed: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
}
