import Darwin
import Foundation

private struct RawInterfaceSnapshot {
    let name: String
    let index: UInt32
    let flags: UInt32
    let mtu: UInt32
    let macAddress: String?
    let ipv4Addresses: [String]
    let ipv6Addresses: [String]
    let counters: InterfaceCounters
}

private struct LinkLayerSnapshot {
    let index: UInt32
    let flags: UInt32
    let mtu: UInt32
    let macAddress: String?
    let counters: InterfaceCounters
}

final class NetworkSampler {
    private var previousSnapshots: [String: (counters: InterfaceCounters, timestamp: TimeInterval)] = [:]
    private let wifiInfoProvider: WifiInfoProvider

    init(wifiInfoProvider: WifiInfoProvider) {
        self.wifiInfoProvider = wifiInfoProvider
    }

    func snapshot(now: TimeInterval = Date().timeIntervalSince1970) -> [InterfaceSnapshot] {
        let current = readRawSnapshots()
        var output: [InterfaceSnapshot] = []
        output.reserveCapacity(current.count)

        for item in current {
            var inRate = 0.0
            var outRate = 0.0

            if let previous = previousSnapshots[item.name] {
                let deltaTime = max(0.001, now - previous.timestamp)
                let inDelta = counterDelta(current: item.counters.inputBytes, previous: previous.counters.inputBytes)
                let outDelta = counterDelta(current: item.counters.outputBytes, previous: previous.counters.outputBytes)
                inRate = (Double(inDelta) * 8.0) / deltaTime
                outRate = (Double(outDelta) * 8.0) / deltaTime
            }

            previousSnapshots[item.name] = (item.counters, now)
            let kind = InterfaceKind.detect(name: item.name, isWifi: wifiInfoProvider.isWifi(interface: item.name))

            output.append(
                InterfaceSnapshot(
                    name: item.name,
                    index: item.index,
                    flags: item.flags,
                    mtu: item.mtu,
                    macAddress: item.macAddress,
                    ipv4Addresses: item.ipv4Addresses,
                    ipv6Addresses: item.ipv6Addresses,
                    kind: kind,
                    counters: item.counters,
                    inBitsPerSecond: inRate,
                    outBitsPerSecond: outRate
                )
            )
        }

        output.sort { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return output
    }

    func wifiDetails(for interface: String) -> WifiDetails? {
        wifiInfoProvider.details(for: interface)
    }

    private func readRawSnapshots() -> [RawInterfaceSnapshot] {
        var rawListPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&rawListPointer) == 0, let first = rawListPointer else {
            return []
        }
        defer { freeifaddrs(rawListPointer) }

        var linkByName: [String: LinkLayerSnapshot] = [:]
        var flagsByName: [String: UInt32] = [:]
        var indexByName: [String: UInt32] = [:]
        var ipv4ByName: [String: Set<String>] = [:]
        var ipv6ByName: [String: Set<String>] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let node = cursor {
            let ifa = node.pointee
            defer { cursor = ifa.ifa_next }

            let name = String(cString: ifa.ifa_name)
            let flags = UInt32(ifa.ifa_flags)
            flagsByName[name] = flags

            if indexByName[name] == nil {
                indexByName[name] = if_nametoindex(ifa.ifa_name)
            }

            guard let address = ifa.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)

            switch family {
            case AF_LINK:
                var counters = InterfaceCounters.zero
                var mtu: UInt32 = 0

                if let ifaData = ifa.ifa_data {
                    let ifData = ifaData.assumingMemoryBound(to: if_data.self).pointee
                    mtu = UInt32(ifData.ifi_mtu)
                    counters = InterfaceCounters(
                        inputBytes: UInt64(ifData.ifi_ibytes),
                        outputBytes: UInt64(ifData.ifi_obytes),
                        inputPackets: UInt64(ifData.ifi_ipackets),
                        outputPackets: UInt64(ifData.ifi_opackets),
                        inputErrors: UInt64(ifData.ifi_ierrors),
                        outputErrors: UInt64(ifData.ifi_oerrors),
                        inputDrops: UInt64(ifData.ifi_iqdrops),
                        collisions: UInt64(ifData.ifi_collisions),
                        crcErrors: UInt64(ifData.ifi_ierrors)
                    )
                }

                let candidate = LinkLayerSnapshot(
                    index: indexByName[name] ?? 0,
                    flags: flags,
                    mtu: mtu,
                    macAddress: macAddress(from: address),
                    counters: counters
                )

                if let existing = linkByName[name] {
                    if candidate.counters.totalBytes >= existing.counters.totalBytes {
                        linkByName[name] = candidate
                    }
                } else {
                    linkByName[name] = candidate
                }

            case AF_INET:
                if let ip = numericAddress(from: address, length: socklen_t(MemoryLayout<sockaddr_in>.size)) {
                    ipv4ByName[name, default: []].insert(ip)
                }

            case AF_INET6:
                if let ip = numericAddress(from: address, length: socklen_t(MemoryLayout<sockaddr_in6>.size)) {
                    ipv6ByName[name, default: []].insert(ip)
                }

            default:
                break
            }
        }

        let allNames = Set(flagsByName.keys)
            .union(linkByName.keys)
            .union(ipv4ByName.keys)
            .union(ipv6ByName.keys)

        var snapshots: [RawInterfaceSnapshot] = []
        snapshots.reserveCapacity(allNames.count)

        for name in allNames {
            let link = linkByName[name]
            let ipv4 = Array(ipv4ByName[name] ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let ipv6 = Array(ipv6ByName[name] ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }

            snapshots.append(
                RawInterfaceSnapshot(
                    name: name,
                    index: link?.index ?? (indexByName[name] ?? 0),
                    flags: link?.flags ?? (flagsByName[name] ?? 0),
                    mtu: link?.mtu ?? 0,
                    macAddress: link?.macAddress,
                    ipv4Addresses: ipv4,
                    ipv6Addresses: ipv6,
                    counters: link?.counters ?? .zero
                )
            )
        }

        return snapshots
    }

    private func numericAddress(from address: UnsafePointer<sockaddr>, length: socklen_t) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        guard result == 0 else { return nil }
        let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func macAddress(from address: UnsafePointer<sockaddr>) -> String? {
        let sdlPointer = UnsafeMutableRawPointer(mutating: address).assumingMemoryBound(to: sockaddr_dl.self)
        let sdl = sdlPointer.pointee

        let nameLength = Int(sdl.sdl_nlen)
        let addressLength = Int(sdl.sdl_alen)
        guard addressLength > 0 else { return nil }

        return withUnsafePointer(to: &sdlPointer.pointee.sdl_data) { pointer in
            let base = UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self)
            var parts: [String] = []
            parts.reserveCapacity(addressLength)

            for idx in 0..<addressLength {
                let byte = base[nameLength + idx]
                parts.append(String(format: "%02x", byte))
            }

            return parts.joined(separator: ":")
        }
    }

    private func counterDelta(current: UInt64, previous: UInt64) -> UInt64 {
        current &- previous
    }
}
