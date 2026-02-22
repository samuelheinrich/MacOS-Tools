import Foundation

enum ANSI {
    static let reset = "\u{1B}[0m"
    static let bold = "\u{1B}[1m"
    static let dim = "\u{1B}[2m"
    static let red = "\u{1B}[31m"
    static let green = "\u{1B}[32m"
    static let yellow = "\u{1B}[33m"
    static let blue = "\u{1B}[34m"
    static let cyan = "\u{1B}[36m"
    static let gray = "\u{1B}[90m"
    static let white = "\u{1B}[37m"
    static let popupBackground = "\u{1B}[48;5;236m"
}

struct Renderer {
    private static let sparkChars: [Character] = Array(" ▁▂▃▄▅▆▇█")
    private static let defaultPeakBitsPerSecond: Double = 1_000_000_000

    static func render(state: AppState, size: (rows: Int, cols: Int)) -> String {
        var lines: [String] = []
        let selected = state.selectedInterface

        lines.append(
            "\(ANSI.bold)\(ANSI.cyan)netmon\(ANSI.reset) \(ANSI.dim)| q quit | h help | d details | u unit | g/1-5 window | p/6-8 labels\(ANSI.reset)"
        )

        if let selected {
            lines.append(
                "Selected: \(ANSI.bold)\(selected.name)\(ANSI.reset) [\(selected.kind.rawValue)]  Unit: \(state.unit.label)  Window: \(state.graphWindow.label)  Peaks: \(state.peakLabelInterval.label)"
            )
        } else {
            lines.append("Selected: -  Unit: \(state.unit.label)  Window: \(state.graphWindow.label)  Peaks: \(state.peakLabelInterval.label)")
        }

        lines.append("")

        let contentRows = max(1, size.rows - lines.count)
        lines.append(contentsOf: mainLayout(state: state, size: size, rows: contentRows))

        var frame = fitToScreen(lines: lines, rows: size.rows, cols: size.cols)
        if state.showHelp {
            frame += helpPopupOverlay(size: size)
        }

        return frame
    }

    private static func mainLayout(state: AppState, size: (rows: Int, cols: Int), rows: Int) -> [String] {
        guard rows > 0 else { return [] }

        if rows < 12 {
            return compactLayout(state: state, width: size.cols, rows: rows)
        }

        let separatorRows = 1
        var topRows = max(6, Int(Double(rows) * 0.48))
        var bottomRows = rows - topRows - separatorRows

        if bottomRows < 8 {
            let need = 8 - bottomRows
            topRows = max(6, topRows - need)
            bottomRows = rows - topRows - separatorRows
        }

        if bottomRows < 4 {
            bottomRows = max(0, rows - topRows)
        }

        let topPane = topLayout(state: state, width: size.cols, rows: topRows)
        let separator = "\(ANSI.dim)\(String(repeating: "-", count: max(10, size.cols)))\(ANSI.reset)"
        let bottomPane = maxiGraphLayout(state: state, width: size.cols, rows: bottomRows)

        var output = topPane
        if bottomRows > 0 {
            output.append(separator)
            output.append(contentsOf: bottomPane)
        }

        return output
    }

    private static func compactLayout(state: AppState, width: Int, rows: Int) -> [String] {
        var lines = interfacePane(state: state, width: width, rows: max(4, rows / 2))
        lines.append("")
        lines.append(contentsOf: infoPane(state: state, width: width, rows: max(3, rows - lines.count)))
        return Array(lines.prefix(rows))
    }

    private static func topLayout(state: AppState, width: Int, rows: Int) -> [String] {
        if width < 100 {
            return interfacePane(state: state, width: width, rows: rows)
        }

        let leftWidth = max(48, min(Int(Double(width) * 0.56), width - 32))
        let rightWidth = max(24, width - leftWidth - 1)

        let left = interfacePane(state: state, width: leftWidth, rows: rows)
        let right = infoPane(state: state, width: rightWidth, rows: rows)

        return mergePanes(left: left, right: right, leftWidth: leftWidth, rightWidth: rightWidth, rows: rows)
    }

    private static func interfacePane(state: AppState, width: Int, rows: Int) -> [String] {
        guard rows > 0 else { return [] }

        var lines: [String] = []
        lines.append("\(ANSI.bold)Interfaces\(ANSI.reset)")

        guard !state.interfaces.isEmpty else {
            lines.append("Keine Interfaces gefunden.")
            return Array(lines.prefix(rows))
        }

        let selected = min(max(0, state.selectedIndex), state.interfaces.count - 1)
        let listRows = max(1, rows - 2)
        let start = max(0, min(selected - (listRows / 2), state.interfaces.count - listRows))
        let end = min(start + listRows, state.interfaces.count)

        for index in start..<end {
            let iface = state.interfaces[index]
            let marker = index == selected ? "\(ANSI.yellow)>\(ANSI.reset)" : " "
            let name = pad(iface.name, to: 9)
            let kind = pad(iface.kind.rawValue, to: 8)
            let statusColor = iface.isUp ? ANSI.green : ANSI.red
            let inRate = formatRateCompact(iface.inBitsPerSecond, unit: state.unit)
            let outRate = formatRateCompact(iface.outBitsPerSecond, unit: state.unit)

            lines.append(
                "\(marker) \(name) \(kind) \(statusColor)\(iface.statusLabel)\(ANSI.reset) in \(ANSI.green)\(inRate)\(ANSI.reset) out \(ANSI.blue)\(outRate)\(ANSI.reset)"
            )
        }

        lines.append("\(ANSI.gray)Showing \(start + 1)-\(end) / \(state.interfaces.count)\(ANSI.reset)")
        return Array(lines.prefix(rows))
    }

    private static func infoPane(state: AppState, width: Int, rows: Int) -> [String] {
        guard rows > 0 else { return [] }

        guard let selected = state.selectedInterface else {
            return ["\(ANSI.bold)Info\(ANSI.reset)", "Keine Interface-Details verfügbar."]
        }

        let historyIn = state.historyIn[selected.name] ?? []
        let historyOut = state.historyOut[selected.name] ?? []
        let miniWidth = max(8, width - 20)
        let miniInValues = selectWindow(values: historyIn, window: state.graphWindow, sampleInterval: state.sampleInterval, maxWidth: miniWidth)
        let miniOutValues = selectWindow(values: historyOut, window: state.graphWindow, sampleInterval: state.sampleInterval, maxWidth: miniWidth)
        let miniMax = max(miniInValues.max() ?? 0, miniOutValues.max() ?? 0, selected.inBitsPerSecond, selected.outBitsPerSecond, 1.0)

        var lines: [String] = []
        lines.append("\(ANSI.bold)IP / MAC + Mini Graph\(ANSI.reset)")
        lines.append("MAC : \(selected.macAddress ?? "-")")
        lines.append("IPv4: \(joinedAddresses(selected.ipv4Addresses, maxItems: 2))")
        lines.append("IPv6: \(joinedAddresses(selected.ipv6Addresses, maxItems: 1))")
        lines.append("Link: \(formatLinkSpeed(state.linkSpeedBitsByName[selected.name]))")

        if selected.kind == .wifi {
            if let wifi = state.selectedWifiDetails {
                let ssid = wifi.ssid ?? "-"
                let rssi = wifi.rssi.map(String.init) ?? "-"
                let noise = wifi.noise.map(String.init) ?? "-"
                let snr = wifi.snr.map(String.init) ?? "-"
                lines.append("Wi-Fi: SSID \(ssid)")
                lines.append("RSSI \(rssi) dBm | Noise \(noise) dBm | SNR \(snr) dB")
            } else {
                lines.append("Wi-Fi: Details aktuell nicht verfügbar")
            }
        }

        lines.append("")
        lines.append("\(ANSI.bold)Mini Graph (\(state.graphWindow.label))\(ANSI.reset)")
        lines.append(
            "IN  \(ANSI.green)\(sparkline(values: miniInValues, width: miniWidth, maxValue: miniMax))\(ANSI.reset) \(formatRate(selected.inBitsPerSecond, unit: state.unit))"
        )
        lines.append(
            "OUT \(ANSI.blue)\(sparkline(values: miniOutValues, width: miniWidth, maxValue: miniMax))\(ANSI.reset) \(formatRate(selected.outBitsPerSecond, unit: state.unit))"
        )

        lines.append("Pkts in/out: \(selected.counters.inputPackets) / \(selected.counters.outputPackets)")
        lines.append("Drops \(selected.counters.inputDrops) | CRC* \(selected.counters.crcErrors)")

        if state.showDetails {
            lines.append("\(ANSI.dim)index=\(selected.index) mtu=\(selected.mtu) flags=0x\(String(selected.flags, radix: 16))\(ANSI.reset)")
        }

        if lines.count < rows {
            lines.append(contentsOf: Array(repeating: "", count: rows - lines.count))
        }

        return Array(lines.prefix(rows))
    }

    private static func maxiGraphLayout(state: AppState, width: Int, rows: Int) -> [String] {
        guard rows > 0 else { return [] }

        guard let selected = state.selectedInterface else {
            return ["\(ANSI.bold)Maxi Graph\(ANSI.reset)", "Keine Daten verfügbar."]
        }

        let historyIn = state.historyIn[selected.name] ?? []
        let historyOut = state.historyOut[selected.name] ?? []
        let peakBitsPerSecond = max(defaultPeakBitsPerSecond, state.linkSpeedBitsByName[selected.name] ?? 0)

        var lines: [String] = []
        lines.append(
            "\(ANSI.bold)Maxi Graph\(ANSI.reset) \(ANSI.dim)(window \(state.graphWindow.label) | peak \(formatBitsRate(peakBitsPerSecond)) | labels \(state.peakLabelInterval.label) | g/1-5 | p/6-8)\(ANSI.reset)"
        )

        if rows == 1 {
            return lines
        }

        let availableChartRows = max(2, rows - 1)
        let downloadRows = max(2, availableChartRows / 2)
        let uploadRows = max(2, availableChartRows - downloadRows)

        lines.append(contentsOf: blockChart(
            title: "Download",
            values: historyIn,
            currentRate: selected.inBitsPerSecond,
            unit: state.unit,
            color: ANSI.green,
            rows: downloadRows,
            width: width,
            peakBitsPerSecond: peakBitsPerSecond,
            window: state.graphWindow,
            sampleInterval: state.sampleInterval,
            peakLabelInterval: state.peakLabelInterval
        ))

        lines.append(contentsOf: blockChart(
            title: "Upload",
            values: historyOut,
            currentRate: selected.outBitsPerSecond,
            unit: state.unit,
            color: ANSI.blue,
            rows: uploadRows,
            width: width,
            peakBitsPerSecond: peakBitsPerSecond,
            window: state.graphWindow,
            sampleInterval: state.sampleInterval,
            peakLabelInterval: state.peakLabelInterval
        ))

        return Array(lines.prefix(rows))
    }

    private static func blockChart(
        title: String,
        values: [Double],
        currentRate: Double,
        unit: RateUnit,
        color: String,
        rows: Int,
        width: Int,
        peakBitsPerSecond: Double,
        window: GraphWindow,
        sampleInterval: TimeInterval,
        peakLabelInterval: PeakLabelInterval
    ) -> [String] {
        guard rows > 0 else { return [] }

        let chartWidth = max(8, width - 2)
        if rows == 1 {
            return ["\(ANSI.bold)\(title)\(ANSI.reset) \(formatRate(currentRate, unit: unit))"]
        }

        let showPeakLabels = rows >= 4
        let graphRows = max(1, rows - 1 - (showPeakLabels ? 1 : 0))
        let columns = timeSeriesColumns(values: values, window: window, sampleInterval: sampleInterval, width: chartWidth)
        let levels = columns.map { value in
            let ratio = max(0.0, min(1.0, value / peakBitsPerSecond))
            return Int(round(ratio * Double(graphRows)))
        }

        var lines: [String] = []
        lines.append("\(ANSI.bold)\(title)\(ANSI.reset) \(formatRate(currentRate, unit: unit))")

        if showPeakLabels {
            let labelRow = peakLabelRow(
                columns: columns,
                unit: unit,
                window: window,
                sampleInterval: sampleInterval,
                interval: peakLabelInterval
            )
            lines.append("\(ANSI.dim)\(labelRow)\(ANSI.reset)")
        }

        for row in stride(from: graphRows, to: 0, by: -1) {
            var bar = ""
            bar.reserveCapacity(chartWidth)

            for level in levels {
                bar.append(level >= row ? "█" : " ")
            }

            lines.append("\(color)\(bar)\(ANSI.reset)")
        }

        return lines
    }

    private static func mergePanes(left: [String], right: [String], leftWidth: Int, rightWidth: Int, rows: Int) -> [String] {
        var lines: [String] = []
        lines.reserveCapacity(rows)

        for idx in 0..<rows {
            let leftLine = idx < left.count ? left[idx] : ""
            let rightLine = idx < right.count ? right[idx] : ""
            let merged = "\(normalizeLine(leftLine, width: leftWidth)) \(normalizeLine(rightLine, width: rightWidth))"
            lines.append(merged)
        }

        return lines
    }

    private static func normalizeLine(_ line: String, width: Int) -> String {
        let clipped = clipLineToWidth(line, cols: width)
        let visible = visibleLength(clipped)
        if visible >= width {
            return clipped
        }

        return clipped + String(repeating: " ", count: width - visible)
    }

    private static func selectWindow(
        values: [Double],
        window: GraphWindow,
        sampleInterval: TimeInterval,
        maxWidth: Int?
    ) -> [Double] {
        guard !values.isEmpty else {
            if let maxWidth {
                return Array(repeating: 0, count: max(0, maxWidth))
            }
            return []
        }

        let count = window.sampleCount(sampleInterval: sampleInterval, availableSamples: values.count)
        var sliced = Array(values.suffix(count))

        if let maxWidth {
            if sliced.count > maxWidth {
                sliced = Array(sliced.suffix(maxWidth))
            } else if sliced.count < maxWidth {
                let padding = Array(repeating: 0.0, count: maxWidth - sliced.count)
                sliced = padding + sliced
            }
        }

        return sliced
    }

    private static func timeSeriesColumns(
        values: [Double],
        window: GraphWindow,
        sampleInterval: TimeInterval,
        width: Int
    ) -> [Double] {
        guard width > 0 else { return [] }
        guard sampleInterval > 0 else { return Array(repeating: 0, count: width) }

        let targetSamples: Int
        if let seconds = window.seconds {
            targetSamples = max(1, Int((seconds / sampleInterval).rounded(.toNearestOrAwayFromZero)))
        } else {
            targetSamples = width
        }

        var fixedWindow = Array(values.suffix(targetSamples))
        if fixedWindow.count < targetSamples {
            fixedWindow = Array(repeating: 0.0, count: targetSamples - fixedWindow.count) + fixedWindow
        }

        if fixedWindow.count == width {
            return fixedWindow
        }

        if width == 1 {
            return [fixedWindow.last ?? 0.0]
        }

        let maxSourceIndex = fixedWindow.count - 1
        var output: [Double] = []
        output.reserveCapacity(width)

        for column in 0..<width {
            let position = Double(column) / Double(width - 1)
            let sourceIndex = Int(round(position * Double(maxSourceIndex)))
            output.append(fixedWindow[sourceIndex])
        }

        return output
    }

    private static func peakLabelRow(
        columns: [Double],
        unit: RateUnit,
        window: GraphWindow,
        sampleInterval: TimeInterval,
        interval: PeakLabelInterval
    ) -> String {
        guard !columns.isEmpty else { return "" }
        guard columns.count >= 8 else { return String(repeating: " ", count: columns.count) }

        let totalSeconds: Double
        if let windowSeconds = window.seconds {
            totalSeconds = max(windowSeconds, sampleInterval)
        } else {
            totalSeconds = max(Double(columns.count) * sampleInterval, sampleInterval)
        }

        let anchors = peakLabelAnchors(
            columns: columns,
            totalSeconds: totalSeconds,
            intervalSeconds: interval.seconds
        )

        if anchors.isEmpty {
            return String(repeating: " ", count: columns.count)
        }

        var row = [Character](repeating: " ", count: columns.count)
        var lastPlacedColumn = -2
        let minimumSpacing = 3

        for anchor in anchors {
            let label = formatPeakLabelValue(anchor.peakBitsPerSecond, unit: unit)
            guard !label.isEmpty else { continue }

            let labelChars = Array(label)
            var start = anchor.column - (labelChars.count / 2)
            start = max(0, min(columns.count - labelChars.count, start))

            if start <= lastPlacedColumn + minimumSpacing {
                continue
            }

            for offset in 0..<labelChars.count {
                row[start + offset] = labelChars[offset]
            }

            lastPlacedColumn = start + labelChars.count - 1
        }

        return String(row)
    }

    private static func peakLabelAnchors(
        columns: [Double],
        totalSeconds: Double,
        intervalSeconds: Double
    ) -> [(column: Int, peakBitsPerSecond: Double)] {
        guard !columns.isEmpty else { return [] }
        guard intervalSeconds > 0 else { return [] }

        if columns.count == 1 {
            return [(column: 0, peakBitsPerSecond: columns[0])]
        }

        let columnStep = max(
            1,
            Int((intervalSeconds / totalSeconds * Double(columns.count - 1)).rounded(.toNearestOrAwayFromZero))
        )

        var anchors: [(column: Int, peakBitsPerSecond: Double)] = []
        var end = columns.count - 1

        while end >= 0 {
            let start = max(0, end - columnStep + 1)
            let peak = columns[start...end].max() ?? 0.0
            let center = (start + end) / 2
            anchors.append((column: center, peakBitsPerSecond: peak))

            if start == 0 {
                break
            }

            end = start - 1
        }

        return anchors.reversed()
    }

    private static func formatPeakLabelValue(_ bitsPerSecond: Double, unit: RateUnit) -> String {
        guard bitsPerSecond > 0 else { return "" }

        let converted = unit.convert(bitsPerSecond: bitsPerSecond)
        switch converted {
        case 100...:
            return String(format: "%.0f", converted)
        case 10...:
            return String(format: "%.1f", converted)
        default:
            return String(format: "%.2f", converted)
        }
    }

    private static func joinedAddresses(_ values: [String], maxItems: Int) -> String {
        guard !values.isEmpty else { return "-" }

        let head = values.prefix(maxItems)
        let suffix = values.count > maxItems ? " +\(values.count - maxItems)" : ""
        return head.joined(separator: ", ") + suffix
    }

    private static func sparkline(values: [Double], width: Int, maxValue: Double) -> String {
        guard width > 0 else { return "" }

        let points = Array(values.suffix(width))
        let paddingCount = max(0, width - points.count)
        var result = String(repeating: " ", count: paddingCount)

        for value in points {
            let normalized = max(0.0, min(1.0, value / maxValue))
            let bucket = Int(round(normalized * Double(sparkChars.count - 1)))
            result.append(sparkChars[bucket])
        }

        return result
    }

    private static func formatRate(_ bitsPerSecond: Double, unit: RateUnit) -> String {
        let converted = unit.convert(bitsPerSecond: bitsPerSecond)
        if converted >= 100 {
            return String(format: "%7.1f %@", converted, unit.label)
        }
        return String(format: "%7.2f %@", converted, unit.label)
    }

    private static func formatRateCompact(_ bitsPerSecond: Double, unit: RateUnit) -> String {
        let converted = unit.convert(bitsPerSecond: bitsPerSecond)
        switch converted {
        case 1_000...:
            return String(format: "%7.0f", converted)
        case 100...:
            return String(format: "%7.1f", converted)
        default:
            return String(format: "%7.2f", converted)
        }
    }

    private static func formatBitsRate(_ bitsPerSecond: Double) -> String {
        switch bitsPerSecond {
        case 1_000_000_000...:
            return String(format: "%.2f Gbit/s", bitsPerSecond / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.0f Mbit/s", bitsPerSecond / 1_000_000)
        case 1_000...:
            return String(format: "%.0f Kbit/s", bitsPerSecond / 1_000)
        default:
            return String(format: "%.0f bit/s", bitsPerSecond)
        }
    }

    private static func formatLinkSpeed(_ bitsPerSecond: Double?) -> String {
        guard let bitsPerSecond else {
            return "unknown"
        }
        return formatBitsRate(bitsPerSecond)
    }

    private static func pad(_ text: String, to width: Int) -> String {
        if text.count >= width {
            return String(text.prefix(width))
        }
        return text + String(repeating: " ", count: width - text.count)
    }

    private static func helpPopupOverlay(size: (rows: Int, cols: Int)) -> String {
        let content = [
            " netmon Help ",
            " ↑ / ↓  Interface wechseln",
            " h      Hilfe ein/aus (Popup)",
            " d      Detailansicht ein/aus",
            " u      Einheit wechseln",
            " g      Graph-Window umschalten",
            " 1..5   Window direkt: live/5s/10s/30s/5m",
            " p      Peak-Labels umschalten",
            " 6..8   Peak-Labels direkt: 5s/10s/15s",
            " q      Beenden"
        ]

        let innerWidth = min(max(42, size.cols - 12), 76)
        let boxWidth = innerWidth + 2
        let boxHeight = content.count + 2
        let top = max(1, (size.rows - boxHeight) / 2 + 1)
        let left = max(1, (size.cols - boxWidth) / 2 + 1)

        var output = ""
        let borderColor = "\(ANSI.bold)\(ANSI.cyan)"

        output += "\u{1B}[\(top);\(left)H\(borderColor)┌\(String(repeating: "─", count: innerWidth))┐\(ANSI.reset)"

        for (index, rawLine) in content.enumerated() {
            let row = top + index + 1
            let clipped = clipPlain(rawLine, width: innerWidth)
            let padded = clipped + String(repeating: " ", count: max(0, innerWidth - clipped.count))
            output += "\u{1B}[\(row);\(left)H\(borderColor)│\(ANSI.reset)\(ANSI.popupBackground)\(ANSI.white)\(padded)\(ANSI.reset)\(borderColor)│\(ANSI.reset)"
        }

        output += "\u{1B}[\(top + boxHeight - 1);\(left)H\(borderColor)└\(String(repeating: "─", count: innerWidth))┘\(ANSI.reset)"
        output += "\u{1B}[1;1H"

        return output
    }

    private static func clipPlain(_ text: String, width: Int) -> String {
        guard width > 0 else { return "" }
        if text.count <= width {
            return text
        }
        if width == 1 {
            return String(text.prefix(1))
        }
        return String(text.prefix(width - 1)) + "…"
    }

    private static func fitToScreen(lines: [String], rows: Int, cols: Int) -> String {
        let visibleLines = Array(lines.prefix(rows))
        var output = ""

        for row in 0..<rows {
            if row < visibleLines.count {
                output += clipLineToWidth(visibleLines[row], cols: cols)
            }
            output += "\u{1B}[0K"
            if row < rows - 1 {
                output += "\r\n"
            }
        }

        return output
    }

    private static func clipLineToWidth(_ line: String, cols: Int) -> String {
        guard cols > 0 else { return "" }

        var output = ""
        var visibleCount = 0
        var index = line.startIndex
        var insideEscape = false

        while index < line.endIndex {
            let char = line[index]

            if insideEscape {
                output.append(char)
                if ("A"..."Z").contains(char) || ("a"..."z").contains(char) {
                    insideEscape = false
                }
                index = line.index(after: index)
                continue
            }

            if char == "\u{1B}" {
                insideEscape = true
                output.append(char)
                index = line.index(after: index)
                continue
            }

            if visibleCount >= cols {
                break
            }

            output.append(char)
            visibleCount += 1
            index = line.index(after: index)
        }

        if visibleCount >= cols {
            output += ANSI.reset
        }

        return output
    }

    private static func visibleLength(_ line: String) -> Int {
        var length = 0
        var insideEscape = false

        for char in line {
            if insideEscape {
                if ("A"..."Z").contains(char) || ("a"..."z").contains(char) {
                    insideEscape = false
                }
                continue
            }

            if char == "\u{1B}" {
                insideEscape = true
                continue
            }

            length += 1
        }

        return length
    }
}
