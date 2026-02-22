import Foundation

NetmonApp().run()

final class NetmonApp {
    private let terminal = TerminalController()
    private let wifiProvider = WifiInfoProvider()
    private let linkSpeedProvider = LinkSpeedProvider()
    private lazy var sampler = NetworkSampler(wifiInfoProvider: wifiProvider)

    private var state = AppState()
    private var running = true
    private var lastWifiRefresh: TimeInterval = 0

    private let refreshInterval: TimeInterval = 0.10
    private let loopSleepMicroseconds: useconds_t = 5_000
    private let maxHistoryPoints = 4_000

    func run() {
        state.sampleInterval = refreshInterval
        terminal.enter()
        defer { terminal.leave() }

        var nextRefresh = Date().timeIntervalSince1970
        render()

        while running {
            let now = Date().timeIntervalSince1970

            if now >= nextRefresh {
                sampleTick(now: now)
                render()
                nextRefresh = now + refreshInterval
            }

            if let key = terminal.readKey() {
                handleKey(key)
                render()
            }

            usleep(loopSleepMicroseconds)
        }
    }

    private func sampleTick(now: TimeInterval) {
        state.interfaces = sampler.snapshot(now: now)

        if state.interfaces.isEmpty {
            state.selectedIndex = 0
            state.selectedWifiDetails = nil
            state.historyIn.removeAll(keepingCapacity: true)
            state.historyOut.removeAll(keepingCapacity: true)
            return
        }

        if state.selectedIndex >= state.interfaces.count {
            state.selectedIndex = state.interfaces.count - 1
        }

        updateHistory()

        if let selected = state.selectedInterface {
            if let linkSpeed = linkSpeedProvider.speedBitsPerSecond(for: selected.name, now: now) {
                state.linkSpeedBitsByName[selected.name] = linkSpeed
            }
        }

        if let selected = state.selectedInterface, selected.kind == .wifi, now - lastWifiRefresh > 1.0 {
            state.selectedWifiDetails = sampler.wifiDetails(for: selected.name)
            lastWifiRefresh = now
        }

        if state.selectedInterface?.kind != .wifi {
            state.selectedWifiDetails = nil
        }
    }

    private func updateHistory() {
        let activeNames = Set(state.interfaces.map { $0.name })
        state.historyIn = state.historyIn.filter { activeNames.contains($0.key) }
        state.historyOut = state.historyOut.filter { activeNames.contains($0.key) }
        state.linkSpeedBitsByName = state.linkSpeedBitsByName.filter { activeNames.contains($0.key) }

        for iface in state.interfaces {
            var inHistory = state.historyIn[iface.name] ?? []
            inHistory.append(iface.inBitsPerSecond)
            if inHistory.count > maxHistoryPoints {
                inHistory.removeFirst(inHistory.count - maxHistoryPoints)
            }
            state.historyIn[iface.name] = inHistory

            var outHistory = state.historyOut[iface.name] ?? []
            outHistory.append(iface.outBitsPerSecond)
            if outHistory.count > maxHistoryPoints {
                outHistory.removeFirst(outHistory.count - maxHistoryPoints)
            }
            state.historyOut[iface.name] = outHistory
        }
    }

    private func handleKey(_ key: KeyInput) {
        switch key {
        case .up:
            if !state.interfaces.isEmpty {
                state.selectedIndex = (state.selectedIndex - 1 + state.interfaces.count) % state.interfaces.count
                lastWifiRefresh = 0
            }
        case .down:
            if !state.interfaces.isEmpty {
                state.selectedIndex = (state.selectedIndex + 1) % state.interfaces.count
                lastWifiRefresh = 0
            }
        case .character(let char):
            let keyString = String(char).lowercased()
            guard let command = keyString.first else { return }
            switch command {
            case "q":
                running = false
            case "h":
                state.showHelp.toggle()
            case "d":
                state.showDetails.toggle()
            case "u":
                state.unit = state.unit.next()
            case "g":
                state.graphWindow = state.graphWindow.next()
            case "p":
                state.peakLabelInterval = state.peakLabelInterval.next()
            case "1", "2", "3", "4", "5":
                if let selectedWindow = GraphWindow.fromShortcut(command) {
                    state.graphWindow = selectedWindow
                }
            case "6", "7", "8":
                if let selectedPeakLabel = PeakLabelInterval.fromShortcut(command) {
                    state.peakLabelInterval = selectedPeakLabel
                }
            case "k":
                handleKey(.up)
            case "j":
                handleKey(.down)
            default:
                break
            }
        case .left, .right, .escape, .unknown:
            break
        }
    }

    private func render() {
        let size = terminal.size()
        let frame = Renderer.render(state: state, size: size)
        terminal.draw(frame: frame)
    }
}
