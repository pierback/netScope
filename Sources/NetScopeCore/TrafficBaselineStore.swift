import Foundation

public protocol TrafficBaselineStoring {
    func load() throws -> TrafficBaseline
    func save(_ baseline: TrafficBaseline) throws
    func clear() throws
}

public enum TrafficBaselineStoreError: Error, CustomStringConvertible {
    case applicationSupportUnavailable
    case baselineFileTooLarge(limitBytes: Int)

    public var description: String {
        switch self {
        case .applicationSupportUnavailable:
            return "Application Support directory is unavailable"
        case let .baselineFileTooLarge(limitBytes):
            return "Learned baseline file exceeds \(limitBytes) bytes"
        }
    }
}

public struct LocalTrafficBaselineStore: TrafficBaselineStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        self.fileURL = try fileURL ?? Self.defaultFileURL(fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() throws -> TrafficBaseline {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return TrafficBaseline()
        }

        let data = try loadBoundedData()
        var baseline = try decoder.decode(TrafficBaseline.self, from: data)
        baseline.prune()
        return baseline
    }

    public func save(_ baseline: TrafficBaseline) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try encoder.encode(baseline)
        try data.write(to: fileURL, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw TrafficBaselineStoreError.applicationSupportUnavailable
        }

        return applicationSupport
            .appendingPathComponent("NetScope", isDirectory: true)
            .appendingPathComponent("traffic-baseline.json", isDirectory: false)
    }

    private func loadBoundedData() throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        let limitBytes = PowerBudget.maximumBaselineFileBytes
        let data = try handle.read(upToCount: limitBytes + 1) ?? Data()
        guard data.count <= limitBytes else {
            throw TrafficBaselineStoreError.baselineFileTooLarge(limitBytes: limitBytes)
        }

        return data
    }
}
