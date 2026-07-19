//  Created for MeatPad selection color hooks.
//
//  STTextView hardcoded the selection highlight's active/inactive colors to
//  NSColor.selectedTextBackgroundColor / .unemphasizedSelectedTextBackgroundColor.
//  This adds `selectedTextBackgroundColor` / `unemphasizedSelectedTextBackgroundColor`
//  (both nil-by-default, meaning "use the system color") so MeatPad can theme
//  selection highlights without forking the drawing logic.
//
//  STSelectionHighlightView.shouldUseEmphasizedColor requires `window.isKeyWindow`
//  -- without a real display, an offscreen NSWindow's key state is unreliable in
//  headless CI, so the emphasized (active/first-responder) rendering path isn't
//  exercised end-to-end here. What IS exercised: the color-resolution logic
//  (nil -> system default, non-nil -> custom color threaded onto the highlight
//  view's emphasizedColor/unemphasizedColor) and the actual rendered
//  backgroundColor on the unemphasized (no-key-window) path, which is the one
//  headless tests can reliably reach.

#if os(macOS)
    import AppKit
    import XCTest
    @testable import STTextViewAppKit

    final class SelectionColorTests: XCTestCase {

        @MainActor
        private func makeTextView() -> STTextView {
            let textView = STTextView()
            textView.frame = CGRect(x: 0, y: 0, width: 400, height: 100)
            textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = true
            textView.setString("Hello, World!")
            return textView
        }

        /// Selects some text and forces the same layout pass STTextView uses
        /// internally (textViewportLayoutController -> updateSelectedRangeHighlight()).
        @MainActor
        private func selectAndLayout(_ textView: STTextView) {
            textView.setSelectedRange(NSRange(location: 0, length: 5))
            textView.layoutViewport()
        }

        @MainActor
        private func highlightView(in textView: STTextView) -> STSelectionHighlightView? {
            textView.selectionView.subviews.compactMap { $0 as? STSelectionHighlightView }.first
        }

        @MainActor
        func testNilColorsResolveToSystemDefaults() {
            let textView = makeTextView()
            XCTAssertNil(textView.selectedTextBackgroundColor)
            XCTAssertNil(textView.unemphasizedSelectedTextBackgroundColor)

            selectAndLayout(textView)

            guard let highlight = highlightView(in: textView) else {
                return XCTFail("expected a selection highlight view after selecting text")
            }
            XCTAssertEqual(highlight.emphasizedColor, .selectedTextBackgroundColor)
            XCTAssertEqual(highlight.unemphasizedColor, .unemphasizedSelectedTextBackgroundColor)
        }

        @MainActor
        func testCustomColorsAreThreadedOntoTheHighlightView() {
            let textView = makeTextView()
            textView.selectedTextBackgroundColor = .red
            textView.unemphasizedSelectedTextBackgroundColor = .blue

            selectAndLayout(textView)

            guard let highlight = highlightView(in: textView) else {
                return XCTFail("expected a selection highlight view after selecting text")
            }
            XCTAssertEqual(highlight.emphasizedColor, .red)
            XCTAssertEqual(highlight.unemphasizedColor, .blue)
        }

        /// Without a key window, STSelectionHighlightView.shouldUseEmphasizedColor
        /// is false (see Overlays/STSelectionHighlightView.swift), so the rendered
        /// `backgroundColor` uses the unemphasized color -- this is the one path
        /// headless tests can observe end-to-end.
        @MainActor
        func testUnemphasizedColorDrivesRenderedBackgroundWithoutKeyWindow() {
            let textView = makeTextView()
            textView.unemphasizedSelectedTextBackgroundColor = .blue

            selectAndLayout(textView)

            guard let highlight = highlightView(in: textView) else {
                return XCTFail("expected a selection highlight view after selecting text")
            }
            XCTAssertNil(textView.window, "sanity: this test intentionally never attaches a window")
            XCTAssertEqual(highlight.backgroundColor, .blue)
        }

        @MainActor
        func testNilUnemphasizedColorRendersSystemDefaultWithoutKeyWindow() {
            let textView = makeTextView()

            selectAndLayout(textView)

            guard let highlight = highlightView(in: textView) else {
                return XCTFail("expected a selection highlight view after selecting text")
            }
            XCTAssertEqual(highlight.backgroundColor, .unemphasizedSelectedTextBackgroundColor)
        }
    }
#endif
