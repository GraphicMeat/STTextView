//  Repro attempt #2 for MeatPad click-caret bug, this time through FULL window
//  event routing (window.sendEvent), with MeatPad's clip-view
//  NSClickGestureRecognizer attached — replicating CodeEditor.makeNSView's
//  "click below short document" setup. The earlier MouseCaretTests called
//  textView.mouseDown(with:) directly, which skips gesture recognizers.

#if os(macOS)
    import AppKit
    import XCTest
    @testable import STTextViewAppKit

    final class ClickThroughGestureTests: XCTestCase {

        /// Mimics CodeEditor.Coordinator.clickBelowText verbatim.
        @MainActor
        final class ClickTarget: NSObject {
            weak var textView: STTextView?
            var fired = 0
            var firedInsideFrame = 0

            @objc func clickBelowText(_ gesture: NSClickGestureRecognizer) {
                fired += 1
                guard let textView, let clipView = gesture.view else { return }
                if textView.frame.contains(gesture.location(in: clipView)) {
                    firedInsideFrame += 1
                    return
                }
                textView.window?.makeFirstResponder(textView)
                textView.textSelection = NSRange(location: (textView.text as NSString? ?? "").length, length: 0)
            }
        }

        @MainActor
        private func makeStack(withGesture: Bool) -> (NSWindow, NSScrollView, STTextView, ClickTarget) {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            let scrollView = STTextView.scrollableTextView()
            scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
            let textView = scrollView.documentView as! STTextView
            textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            window.contentView = scrollView
            textView.setString("alpha bravo charlie\ndelta echo foxtrot\ngolf hotel india")
            textView.layoutViewport()

            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)

            let target = ClickTarget()
            target.textView = textView
            if withGesture {
                let click = NSClickGestureRecognizer(target: target, action: #selector(ClickTarget.clickBelowText(_:)))
                scrollView.contentView.addGestureRecognizer(click)
            }
            return (window, scrollView, textView, target)
        }

        /// Sends a full down+up pair through NSWindow.sendEvent so gesture
        /// recognizers participate, exactly like a real user click.
        @MainActor
        private func sendClick(at pointInContent: CGPoint, textView: STTextView, window: NSWindow) {
            let pointInWindow = textView.contentView.convert(pointInContent, to: nil)
            let time = ProcessInfo.processInfo.systemUptime
            let down = NSEvent.mouseEvent(
                with: .leftMouseDown, location: pointInWindow, modifierFlags: [],
                timestamp: time, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            )!
            let up = NSEvent.mouseEvent(
                with: .leftMouseUp, location: pointInWindow, modifierFlags: [],
                timestamp: time + 0.05, windowNumber: window.windowNumber, context: nil,
                eventNumber: 2, clickCount: 1, pressure: 0
            )!
            window.sendEvent(down)
            window.sendEvent(up)
            // Let any delayed gesture-recognizer callbacks run.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }



        /// Validates the hitTest-based dead-space discrimination MeatPad's fixed
        /// clickBelowText guard relies on: a point on text hit-tests into the text
        /// view subtree; a point in the dead space below a short document does not.
        @MainActor
        func testHitTestDiscriminatesTextFromDeadSpace() {
            let (_, scrollView, textView, _) = makeStack(withGesture: false)
            let clipView = scrollView.contentView

            // Point inside line 1 of the text.
            let onText = textView.contentView.convert(CGPoint(x: 40, y: 8), to: clipView.superview)
            let hitOnText = clipView.hitTest(onText)
            XCTAssertNotNil(hitOnText)
            XCTAssertTrue(hitOnText!.isDescendant(of: textView),
                          "click on text must hit the text view subtree, hit \(type(of: hitOnText!))")

            // Point in the dead space far below the 3-line document.
            let below = clipView.convert(CGPoint(x: 40, y: 250), to: clipView.superview)
            let hitBelow = clipView.hitTest(below)
            if let hitBelow {
                XCTAssertFalse(hitBelow.isDescendant(of: textView),
                               "dead-space click must NOT hit the text view subtree, hit \(type(of: hitBelow))")
            } // nil is fine too: guard treats nil as "no action"... verify frame really is short
            XCTAssertLessThan(textView.frame.height, 250, "precondition: document must not fill the clip view")
        }

    }
#endif
