import Darwin
import Foundation

struct InterfaceCounters {
    let inputBytes: UInt64
    let outputBytes: UInt64
    let inputPackets: UInt64
    let outputPackets: UInt64
    let inputErrors: UInt64
    let outputErrors: UInt64
    let inputDrops: UInt64
    let collisions: UInt64
    let crcErrors: UInt64

    static let zero = InterfaceCounters(
        inputBytes: 0,
        outputBytes: 0,
        inputPackets: 0,
        outputPackets: 0,
        inputErrors: 0,
        outputErrors: 0,
        inputDrops: 0,
        collisions: 0,
        crcErrors: 0
    )

    var totalBytes: UInt64 { inputBytes &+ outputBytes }
}

enum InterfaceKind: String {
    case wifi = "Wi-Fi"
    case ethernet = "Ethernet"
    case loopback = "Loopback"
    case tunnel = "Tunnel"
    case bridge = "Bridge"
    case virtual = "Virtual"
    case unknown = "Unknown"

    static func detect(name: String, isWifi: Bool) -> InterfaceKind {
        if isWifi { return .wifi }
        if name.hasPrefix("lo") { return .loopback }
        if name.hasPrefix("utun") || name.hasPrefix("gif") || name.hasPrefix("stf") || name.hasPrefix("ipsec") {
            return .tunnel
        }
        if name.hasPrefix("bridge") { return .bridge }
        if name.hasPrefix("vnic") || name.hasPrefix("awdl") || name.hasPrefix("llw") || name.hasPrefix("anpi") {
            return .virtual
        }
        if name.hasPrefix("en") { return .ethernet }
        return .unknown
    }
}

struct InterfaceSnapshot {
    let name: String
    let index: UInt32
    let flags: UInt32
    let mtu: UInt32
    let macAddress: String?
    let ipv4Addresses: [String]
    let ipv6Addresses: [String]
    let kind: InterfaceKind
    let counters: InterfaceCounters
    let inBitsPerSecond: Double
    let outBitsPerSecond: Double

    var isUp: Bool { (flags & UInt32(IFF_UP)) != 0 }
    var isRunning: Bool { (flags & UInt32(IFF_RUNNING)) != 0 }
    var isLoopback: Bool { (flags & UInt32(IFF_LOOPBACK)) != 0 }

    var statusLabel: String {
        if isUp && isRunning { return "UP" }
        if isUp { return "UP*" }
        return "DOWN"
    }
}

struct WifiDetails {
    let ssid: String?
    let rssi: Int?
    let noise: Int?
    let snr: Int?
    let txRateMbps: Double?

    var isConnected: Bool {
        guard let ssid, !ssid.isEmpty else { return false }
        return true
    }
}

enum RateUnit: CaseIterable {
    case kilobits
    case megabits
    case gigabits
    case kilobytes
    case megabytes

    var label: String {
        switch self {
        case .kilobits: return "Kbit/s"
        case .megabits: return "Mbit/s"
        case .gigabits: return "Gbit/s"
        case .kilobytes: return "KB/s"
        case .megabytes: return "MB/s"
        }
    }

    func convert(bitsPerSecond: Double) -> Double {
        switch self {
        case .kilobits:
            return bitsPerSecond / 1_000.0
        case .megabits:
            return bitsPerSecond / 1_000_000.0
        case .gigabits:
            return bitsPerSecond / 1_000_000_000.0
        case .kilobytes:
            return bitsPerSecond / 8_000.0
        case .megabytes:
            return bitsPerSecond / 8_000_000.0
        }
    }

    func next() -> RateUnit {
        switch self {
        case .kilobits: return .megabits
        case .megabits: return .gigabits
        case .gigabits: return .kilobytes
        case .kilobytes: return .megabytes
        case .megabytes: return .kilobits
        }
    }
}

enum GraphWindow: CaseIterable {
    case live
    case seconds5
    case seconds10
    case seconds30
    case minutes5

    var label: String {
        switch self {
        case .live: return "live"
        case .seconds5: return "5s"
        case .seconds10: return "10s"
        case .seconds30: return "30s"
        case .minutes5: return "5m"
        }
    }

    var seconds: Double? {
        switch self {
        case .live: return nil
        case .seconds5: return 5
        case .seconds10: return 10
        case .seconds30: return 30
        case .minutes5: return 300
        }
    }

    func next() -> GraphWindow {
        switch self {
        case .live: return .seconds5
        case .seconds5: return .seconds10
        case .seconds10: return .seconds30
        case .seconds30: return .minutes5
        case .minutes5: return .live
        }
    }

    static func fromShortcut(_ char: Character) -> GraphWindow? {
        switch char {
        case "1": return .live
        case "2": return .seconds5
        case "3": return .seconds10
        case "4": return .seconds30
        case "5": return .minutes5
        default: return nil
        }
    }

    func sampleCount(sampleInterval: TimeInterval, availableSamples: Int) -> Int {
        guard availableSamples > 0 else { return 0 }
        guard let seconds else { return availableSamples }

        let estimated = Int((seconds / sampleInterval).rounded(.toNearestOrAwayFromZero))
        return max(1, min(availableSamples, estimated))
    }
}

enum PeakLabelInterval: CaseIterable {
    case seconds5
    case seconds10
    case seconds15

    var label: String {
        switch self {
        case .seconds5: return "5s"
        case .seconds10: return "10s"
        case .seconds15: return "15s"
        }
    }

    var seconds: Double {
        switch self {
        case .seconds5: return 5
        case .seconds10: return 10
        case .seconds15: return 15
        }
    }

    func next() -> PeakLabelInterval {
        switch self {
        case .seconds5: return .seconds10
        case .seconds10: return .seconds15
        case .seconds15: return .seconds5
        }
    }

    static func fromShortcut(_ char: Character) -> PeakLabelInterval? {
        switch char {
        case "6": return .seconds5
        case "7": return .seconds10
        case "8": return .seconds15
        default: return nil
        }
    }
}

struct AppState {
    var interfaces: [InterfaceSnapshot] = []
    var selectedIndex: Int = 0
    var showHelp: Bool = false
    var showDetails: Bool = false
    var unit: RateUnit = .megabits
    var graphWindow: GraphWindow = .live
    var peakLabelInterval: PeakLabelInterval = .seconds5
    var sampleInterval: TimeInterval = 0.10
    var linkSpeedBitsByName: [String: Double] = [:]
    var historyIn: [String: [Double]] = [:]
    var historyOut: [String: [Double]] = [:]
    var selectedWifiDetails: WifiDetails?

    var selectedInterface: InterfaceSnapshot? {
        guard !interfaces.isEmpty else { return nil }
        let idx = min(max(0, selectedIndex), interfaces.count - 1)
        return interfaces[idx]
    }
}
