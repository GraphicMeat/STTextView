//  Repro attempt for MeatPad bug: clicking in the editor does not move the
//  caret (arrow keys do). Exercises STTextView.mouseDown's plain-click path
//  headlessly: synthesized .leftMouseDown NSEvent routed through mouseDown(with:),
//  asserting the caret lands on the clicked line.

#if os(macOS)
    import AppKit
    import XCTest
    @testable import STTextViewAppKit

    final class MouseCaretTests: XCTestCase {

        @MainActor
        private func makeWindowedTextView() -> (NSWindow, STTextView) {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            let scrollView = STTextView.scrollableTextView()
            scrollView.frame = window.contentLayoutRect
            let textView = scrollView.documentView as! STTextView
            textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            window.contentView = scrollView
            textView.setString("alpha bravo charlie\ndelta echo foxtrot\ngolf hotel india")
            textView.layoutViewport()
            return (window, textView)
        }

        @MainActor
        private func click(_ textView: STTextView, at pointInContent: CGPoint, in window: NSWindow) {
            let pointInWindow = textView.contentView.convert(pointInContent, to: nil)
            let event = NSEvent.mouseEvent(
                with: .leftMouseDown, location: pointInWindow, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            )!
            textView.mouseDown(with: event)
        }

        /// Caret starts at end of document (line 3); a click on line 1 must move it there.
        @MainActor
        func testPlainClickMovesCaretToClickedLine() {
            let (window, textView) = makeWindowedTextView()
            textView.setSelectedRange(NSRange(location: 57, length: 0)) // end of doc

            // Line height ~16pt at 13pt monospaced; y=8 is inside line 1. x=40 is
            // ~column 6 ("bravo").
            click(textView, at: CGPoint(x: 40, y: 8), in: window)

            let caret = textView.selectedRange().location
            XCTAssertLessThan(caret, 19, "caret should be on line 1 (offset <19), got \(caret)")
            XCTAssertGreaterThan(caret, 0, "caret should have moved off offset 0 sentinel, got \(caret)")
        }

        /// Same click but on line 2 — guards against off-by-one-line mapping.
        @MainActor
        func testPlainClickMovesCaretToSecondLine() {
            let (window, textView) = makeWindowedTextView()
            textView.setSelectedRange(NSRange(location: 0, length: 0))

            click(textView, at: CGPoint(x: 40, y: 24), in: window)

            let caret = textView.selectedRange().location
            XCTAssertGreaterThanOrEqual(caret, 20, "caret should be on line 2 (offset >=20), got \(caret)")
            XCTAssertLessThan(caret, 39, "caret should be on line 2 (offset <39), got \(caret)")
        }
    }
#endif
