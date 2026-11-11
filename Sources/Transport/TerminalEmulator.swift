import Foundation

/// A small, stateful terminal emulator.
///
/// Replaces the earlier stateless "strip the escapes" approach, which
/// could not work correctly: output arrives in arbitrary chunks, so a
/// carriage return or escape sequence at a chunk boundary had no way to
/// affect text already emitted. This keeps a line buffer and a cursor,
/// so in-place rewrites (shell prompts, progress spinners) land where
/// they should.
///
/// Scope is deliberately limited to what an SSH session needs: text,
/// cursor column moves, line erase, newlines, backspace, and ignoring
/// colour/attribute sequences. Full-screen apps (vim, htop) are out of
/// scope and documented as a known limitation.
public final class TerminalEmulator: @unchecked Sendable {

    /// Rendered lines. The last element is the line being written.
    private var lines: [String] = [""]
    private var cursorColumn: Int = 0
    /// Partial escape sequence carried across chunk boundaries.
    private var pendingEscape: String = ""
    private let maxLines: Int
    private let lock = NSLock()

    public init(maxLines: Int = 5000) {
        self.maxLines = maxLines
    }

    /// Feeds raw output and returns the full rendered text.
    ///
    /// Iterates over unicode *scalars*, not Characters: Swift treats
    /// "\r\n" as a single Character (grapheme cluster), so a
    /// Character-based loop would never match CR or LF individually and
    /// would write the pair into the line as literal text.
    public func feed(_ text: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        let scalars = Array((pendingEscape + text).unicodeScalars)
        pendingEscape = ""

        var i = 0
        while i < scalars.count {
            let sc = scalars[i]

            if sc == "\u{1B}" {
                // Consume a complete escape sequence; if the chunk ends
                // mid-sequence, stash it for the next feed.
                if let consumed = applyEscape(scalars, from: i) {
                    i = consumed
                } else {
                    pendingEscape = String(String.UnicodeScalarView(scalars[i...]))
                    break
                }
                continue
            }

            switch sc {
            case "\n":
                newline()
            case "\r":
                cursorColumn = 0
            case "\u{08}", "\u{7F}":
                if cursorColumn > 0 { cursorColumn -= 1 }
            case "\u{07}":
                break // bell: ignore
            case "\t":
                let next = ((cursorColumn / 8) + 1) * 8
                write(String(repeating: " ", count: next - cursorColumn))
            default:
                write(String(Character(sc)))
            }
            i += 1
        }

        return lines.joined(separator: "\n")
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        lines = [""]
        cursorColumn = 0
        pendingEscape = ""
    }

    // MARK: - Primitives

    /// Writes text at the cursor, overwriting what is already there.
    private func write(_ s: String) {
        var line = Array(lines[lines.count - 1])
        if cursorColumn > line.count {
            line.append(contentsOf: Array(repeating: " ", count: cursorColumn - line.count))
        }
        for ch in s {
            if cursorColumn < line.count {
                line[cursorColumn] = ch
            } else {
                line.append(ch)
            }
            cursorColumn += 1
        }
        lines[lines.count - 1] = String(line)
    }

    private func newline() {
        lines.append("")
        cursorColumn = 0
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    private func eraseToEndOfLine() {
        var line = Array(lines[lines.count - 1])
        if cursorColumn < line.count {
            line.removeSubrange(cursorColumn..<line.count)
            lines[lines.count - 1] = String(line)
        }
    }

    private func eraseLine() {
        lines[lines.count - 1] = ""
        cursorColumn = 0
    }

    /// Applies the escape sequence starting at index `start`.
    /// Returns the index just past it, or nil if the sequence is
    /// incomplete (needs more input).
    private func applyEscape(_ s: [Unicode.Scalar], from start: Int) -> Int? {
        var i = start + 1
        guard i < s.count else { return nil }

        let introducer = s[i]
        if introducer == "[" {
            // CSI: ESC [ params final
            i += 1
            var params = ""
            while i < s.count {
                let v = s[i].value
                if v >= 0x40, v <= 0x7E {
                    applyCSI(final: Character(s[i]), params: params)
                    return i + 1
                }
                params.unicodeScalars.append(s[i])
                i += 1
            }
            return nil // incomplete
        }

        if introducer == "]" {
            // OSC: ESC ] ... terminated by BEL or ESC backslash
            i += 1
            while i < s.count {
                if s[i] == "\u{07}" { return i + 1 }
                if s[i] == "\u{1B}" {
                    if i + 1 < s.count, s[i + 1] == "\\" { return i + 2 }
                    return nil
                }
                i += 1
            }
            return nil // incomplete
        }

        // Two-character escape (e.g. ESC =, ESC >): skip it.
        return i + 1
    }

    private func applyCSI(final: Character, params: String) {
        // Strip private-mode markers like '?' so "?25l" parses.
        let numeric = params.filter { $0.isNumber || $0 == ";" }
        let values = numeric.split(separator: ";").compactMap { Int($0) }
        let first = values.first ?? 0

        switch final {
        case "G":
            // Cursor horizontal absolute (1-based).
            cursorColumn = max(0, (first == 0 ? 1 : first) - 1)
        case "K":
            // Erase in line: 0 = to end, 1 = to start, 2 = whole line.
            switch first {
            case 2: eraseLine()
            case 1: break // rarely used by shells; left as-is
            default: eraseToEndOfLine()
            }
        case "C":
            cursorColumn += max(1, first)
        case "D":
            cursorColumn = max(0, cursorColumn - max(1, first))
        case "J":
            // Erase display: treat as erase current line onward.
            eraseToEndOfLine()
        case "m", "h", "l", "n", "r", "t", "A", "B", "H", "f", "P", "@", "S", "T", "X", "d":
            // Colours, modes, cursor row moves, insert/delete: ignored.
            break
        default:
            break
        }
    }
}
