import Foundation

final class LinkSpeedProvider {
    private struct CachedSpeed {
        let speedBitsPerSecond: Double?
        let timestamp: TimeInterval
    }

    private var cache: [String: CachedSpeed] = [:]
    private let cacheTTL: TimeInterval = 15.0

    func speedBitsPerSecond(for interface: String, now: TimeInterval = Date().timeIntervalSince1970) -> Double? {
        if let cached = cache[interface], now - cached.timestamp <= cacheTTL {
            return cached.speedBitsPerSecond
        }

        guard let output = run(path: "/sbin/ifconfig", arguments: [interface]), !output.isEmpty else {
            cache[interface] = CachedSpeed(speedBitsPerSecond: nil, timestamp: now)
            return nil
        }

        let speed = parseSpeedBitsPerSecond(from: output)
        cache[interface] = CachedSpeed(speedBitsPerSecond: speed, timestamp: now)
        return speed
    }

    private func parseSpeedBitsPerSecond(from text: String) -> Double? {
        var maxBitsPerSecond: Double = 0

        // Example matches: 1000baseT, 2500base-T, 10Gbase-T, 25Gbase-CR
        let patterns: [(pattern: String, multiplier: Double)] = [
            ("([0-9]+(?:\\.[0-9]+)?)\\s*Gbase", 1_000_000_000),
            ("([0-9]+(?:\\.[0-9]+)?)\\s*base", 1_000_000)
        ]

        for (pattern, multiplier) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let speedRange = Range(match.range(at: 1), in: text),
                      let speedValue = Double(text[speedRange]) else {
                    return
                }

                maxBitsPerSecond = max(maxBitsPerSecond, speedValue * multiplier)
            }
        }

        guard maxBitsPerSecond > 0 else {
            return nil
        }

        return maxBitsPerSecond
    }

    private func run(path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
