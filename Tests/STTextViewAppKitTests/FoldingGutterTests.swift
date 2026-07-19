//  Created for MeatPad code folding.
//
//  Task 3: gutter line numbers must stay correct across folds. Folded
//  (collapsed, zero-height) fragments must not get a visible gutter cell,
//  but the running line counter must still advance past them so the line
//  after a fold shows its true document line number.

#if os(macOS)
    import AppKit
    import XCTest
    @testable import STTextViewAppKit

    final class FoldingGutterTests: XCTestCase {

        /// 6 single-line paragraphs with the gutter/line numbers enabled and
        /// a real viewport layout pass forced -- no window needed, mirrors
        /// FoldingTests' headless STTextView setup (`layoutViewport()` only
        /// touches `contentView`'s own frame/bounds, doesn't require being
        /// in a window).
        @MainActor
        private func makeFoldGutterTextView() -> STTextView {
            let textView = STTextView()
            textView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
            textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = true
            textView.showsLineNumbers = true
            textView.setString((1 ... 6).map { "Line \($0)" }.joined(separator: "\n"))
            return textView
        }

        /// Body range for a fold over paragraphs 2-4 (see FoldingTests.bodyRange).
        @MainActor
        private func bodyRange(_ textView: STTextView) -> NSTextRange {
            let string = textView.text! as NSString
            let start = string.range(of: "Line 2").location
            let end = string.range(of: "Line 5").location
            return NSTextRange(NSRange(location: start, length: end - start), in: textView.textContentManager)!
        }

        @MainActor
        private func gutterLineNumberCells(_ textView: STTextView) -> [STGutterLineNumberCell] {
            guard let gutterView = textView.gutterView else {
                return []
            }
            return gutterView.containerView.subviews
                .compactMap { $0 as? STGutterLineNumberCell }
                .sorted { $0.lineNumber < $1.lineNumber }
        }

        @MainActor
        func testGutterLineNumbersSkipButCountFoldedLines() {
            let textView = makeFoldGutterTextView()
            textView.foldedRanges = [bodyRange(textView)]
            textView.layoutViewport()

            let cells = gutterLineNumberCells(textView)

            // Folded lines 2-4 must not get a gutter cell at all (skipped
            // visually), while the surviving cells keep their true document
            // line numbers (counted through the fold, not renumbered 1,2,3).
            XCTAssertEqual(
                cells.map(\.lineNumber),
                [1, 5, 6],
                "lines 2-4 are folded: gutter must show cells for 1, 5, 6 only -- no cell for folded lines, and no undercounting"
            )
        }

        @MainActor
        func testGutterLineNumbersSequentialWithoutFold() {
            // Control: no folding, gutter must show a cell for every line 1...6.
            let textView = makeFoldGutterTextView()
            textView.layoutViewport()

            XCTAssertEqual(gutterLineNumberCells(textView).map(\.lineNumber), [1, 2, 3, 4, 5, 6])
        }
    }
#endif
