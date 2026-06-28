import Foundation

public enum TrafficRateFormatStyle: Sendable {
    case long
    case compact
}

public enum TrafficFormatting: Sendable {
    private static let decimalLocale = Locale(identifier: "en_US_POSIX")
    private static let wholeNumberStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0))
        .locale(decimalLocale)
    private static let shortDecimalStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0 ... 1))
        .locale(decimalLocale)
    private static let singleFractionStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(1))
        .locale(decimalLocale)

    public static func appTraffic(_ app: AppTraffic, style: TrafficRateFormatStyle = .long) -> String {
        switch style {
        case .long:
            return "\(bitsPerSecond(app.bytesInPerSecond, style: .long)) down / \(bitsPerSecond(app.bytesOutPerSecond, style: .long)) up"
        case .compact:
            return "\(bitsPerSecond(app.bytesInPerSecond, style: .compact)) dn / \(bitsPerSecond(app.bytesOutPerSecond, style: .compact)) up"
        }
    }

    public static func bitsPerSecond(_ bytesPerSecond: Int, style: TrafficRateFormatStyle = .long) -> String {
        let bitsPerSecond = Double(bytesPerSecond) * 8

        if bitsPerSecond >= 1_000_000 {
            return formattedRate(bitsPerSecond / 1_000_000, unit: "M", style: style)
        }

        if bitsPerSecond >= 1_000 {
            return formattedRate(bitsPerSecond / 1_000, unit: "K", style: style)
        }

        switch style {
        case .long:
            return "\(Int(bitsPerSecond)) bps"
        case .compact:
            return "\(Int(bitsPerSecond))"
        }
    }

    public static func percent(_ fraction: Double) -> String {
        "\(decimal(fraction * 100))%"
    }

    public static func decimal(_ value: Double) -> String {
        if value < 10 {
            return value.formatted(shortDecimalStyle)
        }

        return value.formatted(wholeNumberStyle)
    }

    public static func baselineMultiplier(_ multiplier: Double) -> String {
        "\(multiplier.formatted(singleFractionStyle))x"
    }

    private static func formattedRate(_ value: Double, unit: String, style: TrafficRateFormatStyle) -> String {
        let formattedValue = decimal(value)

        switch style {
        case .long:
            return "\(formattedValue) \(unit)bps"
        case .compact:
            return "\(formattedValue)\(unit)"
        }
    }
}

public extension Sequence where Element == AppTraffic {
    func totalIncomingBytesPerSecond() -> Int {
        reduce(0) { $0 + $1.bytesInPerSecond }
    }

    func totalOutgoingBytesPerSecond() -> Int {
        reduce(0) { $0 + $1.bytesOutPerSecond }
    }
}
