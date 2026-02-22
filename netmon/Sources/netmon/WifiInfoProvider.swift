import Foundation

final class WifiInfoProvider {
    private let airportPath = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"
    private let cacheTTL: TimeInterval = 2.0

    private var wifiInterfaces: Set<String>
    private var cache: [String: (details: WifiDetails, timestamp: TimeInterval)] = [:]

    init() {
        self.wifiInterfaces = WifiInfoProvider.detectWifiInterfaces()
    }

    func isWifi(interface: String) -> Bool {
        wifiInterfaces.contains(interface)
    }

    func details(for interface: String, now: TimeInterval = Date().timeIntervalSince1970) -> WifiDetails? {
        guard wifiInterfaces.contains(interface) else {
            return nil
        }

        if let cached = cache[interface], now - cached.timestamp <= cacheTTL {
            return cached.details
        }

        guard FileManager.default.isExecutableFile(atPath: airportPath) else {
            return nil
        }

        guard let output = run(path: airportPath, arguments: ["-I"]), !output.isEmpty else {
            return nil
        }

        let details = parseAirportOutput(output)
        cache[interface] = (details, now)
        return details
    }

    private static func detectWifiInterfaces() -> Set<String> {
        guard let output = run(path: "/usr/sbin/networksetup", arguments: ["-listallhardwareports"]) else {
            return []
        }

        var result: Set<String> = []
        var currentIsWifiPort = false

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("Hardware Port:") {
                let value = line.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
                currentIsWifiPort = value.caseInsensitiveCompare("Wi-Fi") == .orderedSame ||
                    value.caseInsensitiveCompare("AirPort") == .orderedSame
                continue
            }

            if currentIsWifiPort && line.hasPrefix("Device:") {
                let device = line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                if !device.isEmpty {
                    result.insert(device)
                }
                currentIsWifiPort = false
            }
        }

        return result
    }

    private static func parseAirportOutput(_ output: String) -> WifiDetails {
        var map: [String: String] = [:]

        for rawLine in output.split(separator: "\n") {
            guard let colon = rawLine.firstIndex(of: ":") else { continue }

            let key = rawLine[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawLine[rawLine.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            map[key] = value
        }

        let ssid = map["SSID"]?.isEmpty == false ? map["SSID"] : nil
        let rssi = map["agrCtlRSSI"].flatMap(Int.init)
        let noise = map["agrCtlNoise"].flatMap(Int.init)
        let snr = (rssi != nil && noise != nil) ? (rssi! - noise!) : nil
        let txRate = map["lastTxRate"].flatMap(Double.init)

        return WifiDetails(ssid: ssid, rssi: rssi, noise: noise, snr: snr, txRateMbps: txRate)
    }

    private static func run(path: String, arguments: [String]) -> String? {
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

    private func parseAirportOutput(_ output: String) -> WifiDetails {
        Self.parseAirportOutput(output)
    }

    private func run(path: String, arguments: [String]) -> String? {
        Self.run(path: path, arguments: arguments)
    }
}
