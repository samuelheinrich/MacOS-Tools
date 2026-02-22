import Darwin
import Foundation

enum KeyInput {
    case up
    case down
    case left
    case right
    case character(Character)
    case escape
    case unknown
}

final class TerminalController {
    private var originalTermios = termios()
    private var originalFlags: Int32 = 0
    private var rawModeEnabled = false
    private var pendingBytes: [UInt8] = []

    func enter() {
        guard !rawModeEnabled else { return }

        originalFlags = fcntl(STDIN_FILENO, F_GETFL)
        _ = tcgetattr(STDIN_FILENO, &originalTermios)

        var raw = originalTermios
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)

        setControlChar(&raw, index: Int(VMIN), value: 0)
        setControlChar(&raw, index: Int(VTIME), value: 0)

        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        _ = fcntl(STDIN_FILENO, F_SETFL, originalFlags | O_NONBLOCK)

        write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[2J\u{1B}[H")
        rawModeEnabled = true
    }

    func leave() {
        guard rawModeEnabled else { return }

        var restored = originalTermios
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &restored)
        _ = fcntl(STDIN_FILENO, F_SETFL, originalFlags)

        write("\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l")
        rawModeEnabled = false
    }

    func size() -> (rows: Int, cols: Int) {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 {
            let rows = max(Int(ws.ws_row), 10)
            let cols = max(Int(ws.ws_col), 40)
            return (rows, cols)
        }

        return (24, 80)
    }

    func draw(frame: String) {
        write("\u{1B}[H\(frame)")
    }

    func readKey() -> KeyInput? {
        pullStdinBytes()
        guard !pendingBytes.isEmpty else { return nil }
        return popKey()
    }

    private func pullStdinBytes() {
        var buffer = [UInt8](repeating: 0, count: 32)

        while true {
            let count = read(STDIN_FILENO, &buffer, buffer.count)
            if count > 0 {
                pendingBytes.append(contentsOf: buffer[0..<Int(count)])
                if count < buffer.count {
                    break
                }
            } else {
                break
            }
        }
    }

    private func popKey() -> KeyInput {
        let first = pendingBytes.removeFirst()

        if first == 0x1B {
            if pendingBytes.count >= 2, pendingBytes[0] == 0x5B {
                _ = pendingBytes.removeFirst()
                let code = pendingBytes.removeFirst()
                switch code {
                case 0x41: return .up
                case 0x42: return .down
                case 0x43: return .right
                case 0x44: return .left
                default: return .unknown
                }
            }
            return .escape
        }

        if first == 0x03 {
            return .character("q")
        }

        if let scalar = UnicodeScalar(Int(first)) {
            return .character(Character(scalar))
        }

        return .unknown
    }

    private func write(_ text: String) {
        text.utf8CString.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            var remaining = buffer.count - 1 // Exclude trailing NUL.

            while remaining > 0 {
                let result = Darwin.write(STDOUT_FILENO, base.advanced(by: offset), remaining)
                if result > 0 {
                    let written = Int(result)
                    offset += written
                    remaining -= written
                    continue
                }

                if result == -1 && errno == EINTR {
                    continue
                }

                if result == -1 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    usleep(1_000)
                    continue
                }

                break
            }
        }
    }

    private func setControlChar(_ term: inout termios, index: Int, value: cc_t) {
        withUnsafeMutablePointer(to: &term.c_cc) { ptr in
            ptr.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { cc in
                cc[index] = value
            }
        }
    }

    deinit {
        leave()
    }
}
