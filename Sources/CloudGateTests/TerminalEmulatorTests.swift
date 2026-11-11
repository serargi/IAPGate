import Foundation
import TestKit
import Transport

func terminalEmulatorSuite() -> TestSuite {
    let s = TestSuite("TerminalEmulator")

    s.test("renders plain text and newlines") { t in
        let e = TerminalEmulator()
        t.expectEqual(e.feed("line1\r\nline2"), "line1\nline2")
    }

    s.test("strips colour sequences") { t in
        let e = TerminalEmulator()
        t.expectEqual(e.feed("\u{1B}[32msgarcia@vm\u{1B}[0m:~$ "), "sgarcia@vm:~$ ")
    }

    s.test("carriage return overwrites the current line in place") { t in
        let e = TerminalEmulator()
        // CR returns to column 0 and subsequent text overwrites what is
        // already there, leaving the tail intact — real terminal
        // behaviour (that's why shells also emit an erase-line).
        t.expectEqual(e.feed("Updating...\rDone."), "Done.ing...")
    }

    s.test("erase-to-end-of-line after CR gives a clean rewrite") { t in
        let e = TerminalEmulator()
        t.expectEqual(e.feed("Updating...\r\u{1B}[KDone."), "Done.")
    }

    s.test("keeps prompts on separate lines across chunks") { t in
        let e = TerminalEmulator()
        // Each Enter press produces CRLF then a new prompt, arriving in
        // separate reads. Prompts must not pile up on one line.
        _ = e.feed("user@host:~$ ")
        _ = e.feed("\r\n")
        let out = e.feed("user@host:~$ ")
        t.expectEqual(out, "user@host:~$ \nuser@host:~$ ")
    }

    s.test("handles an escape split across two chunks") { t in
        let e = TerminalEmulator()
        // "ESC [" arrives, then "32mHi" in the next chunk.
        _ = e.feed("A\u{1B}[")
        let out = e.feed("32mHi")
        t.expectEqual(out, "AHi")
    }

    s.test("backspace moves the cursor back") { t in
        let e = TerminalEmulator()
        t.expectEqual(e.feed("abc\u{08}d"), "abd")
    }

    s.test("cursor-to-column-1 rewrites from the start") { t in
        let e = TerminalEmulator()
        t.expectEqual(e.feed("Updating...\u{1B}[GDone."), "Done.ing...")
    }

    s.test("strips OSC title sequences") { t in
        let e = TerminalEmulator()
        t.expectEqual(e.feed("\u{1B}]0;title\u{07}prompt$ "), "prompt$ ")
    }

    return s
}
