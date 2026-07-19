//  Created for MeatPad code folding spike.
//
//  DECISION: Mechanism A (zero-height `layoutFragmentFrame` override on an
//  NSTextLayoutFragment subclass, installed via NSTextLayoutManagerDelegate)
//  WORKS. Measured: with lines 2-4 collapsed, paragraph 5's fragment
//  y-origin lands exactly where paragraph 2's y-origin sits in the
//  uncollapsed baseline layout (subsequent fragments moved up), and
//  usageBoundsForTextContainer.height shrinks by exactly the height of the
//  three collapsed line fragments. NSTextContentStorage's underlying
//  NSTextStorage is never mutated. See testMechanismA_CollapsedFragmentsHideAndStackingMoves
//  and testMechanismA_DocumentStorageIsNeverMutated below for the evidence.
//  Task 2 builds production folding on mechanism A.

#if os(macOS)
    import AppKit
    import XCTest
    @testable import STTextViewAppKit

    final class FoldingSpikeTests: XCTestCase {

        /// Fragment subclass that reports zero height while leaving the
        /// underlying line fragments (and therefore the text) intact.
        final class CollapsedFragment: NSTextLayoutFragment {
            override var layoutFragmentFrame: CGRect {
                var frame = super.layoutFragmentFrame
                frame.size.height = 0
                return frame
            }
        }

        final class Delegate: NSObject, NSTextLayoutManagerDelegate {
            var collapse: (NSTextRange) -> Bool = { _ in false }

            func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
                if let range = textElement.elementRange, collapse(range) {
                    return CollapsedFragment(textElement: textElement, range: range)
                }
                return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
            }
        }

        private let documentText = "l1\nl2\nl3\nl4\nl5\nl6\n"

        /// Builds an independent NSTextContentStorage -> NSTextLayoutManager -> NSTextContainer
        /// stack (mirrors what STTextView assembles) and lays out fully.
        /// `collapsedLines` names the paragraph text ("l2", "l3", ...) whose
        /// fragment should report zero height.
        private func makeStack(collapsedLines: Set<String>) -> (contentStorage: NSTextContentStorage, layoutManager: NSTextLayoutManager, delegate: Delegate) {
            let contentStorage = NSTextContentStorage()
            contentStorage.textStorage = NSTextStorage(string: documentText)

            let layoutManager = NSTextLayoutManager()
            let textContainer = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
            layoutManager.textContainer = textContainer
            contentStorage.addTextLayoutManager(layoutManager)

            let delegate = Delegate()
            delegate.collapse = { [contentStorage] range in
                let nsRange = NSRange(range, in: contentStorage)
                let paragraphText = (contentStorage.textStorage!.string as NSString)
                    .substring(with: nsRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return collapsedLines.contains(paragraphText)
            }
            layoutManager.delegate = delegate

            layoutManager.ensureLayout(for: layoutManager.documentRange)

            return (contentStorage, layoutManager, delegate)
        }

        private func fragmentFrames(_ layoutManager: NSTextLayoutManager) -> [CGRect] {
            var frames: [CGRect] = []
            layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
                frames.append(fragment.layoutFragmentFrame)
                return true
            }
            return frames
        }

        @MainActor
        func testMechanismA_CollapsedFragmentsHideAndStackingMoves() {
            // Baseline: nothing collapsed.
            let baseline = makeStack(collapsedLines: [])
            let baselineFrames = fragmentFrames(baseline.layoutManager)
            XCTAssertEqual(baselineFrames.count, 6, "expected one fragment per line (l1...l6)")

            let baselineParagraph2Y = baselineFrames[1].origin.y // "l2"

            // Collapse paragraphs 2-4 ("l2", "l3", "l4").
            let collapsed = makeStack(collapsedLines: ["l2", "l3", "l4"])
            let collapsedFrames = fragmentFrames(collapsed.layoutManager)
            XCTAssertEqual(collapsedFrames.count, 6, "fragments still exist for every paragraph, just zero-height")

            // The collapsed fragments themselves report zero height.
            XCTAssertEqual(collapsedFrames[1].size.height, 0, accuracy: 0.001)
            XCTAssertEqual(collapsedFrames[2].size.height, 0, accuracy: 0.001)
            XCTAssertEqual(collapsedFrames[3].size.height, 0, accuracy: 0.001)

            // The key assertion: paragraph 5 ("l5") moved up to occupy the
            // slot paragraph 2 used to have in the uncollapsed baseline --
            // i.e. NSTextLayoutManager positioned it using our overridden
            // zero-height frame, not some internal cached line-height metric.
            let collapsedParagraph5Y = collapsedFrames[4].origin.y
            XCTAssertEqual(collapsedParagraph5Y, baselineParagraph2Y, accuracy: 0.001)

            // usageBoundsForTextContainer shrank by exactly the height that
            // the three collapsed line fragments would otherwise have occupied.
            let baselineLineHeight = baselineFrames[2].origin.y - baselineFrames[1].origin.y // one line's height
            let expectedShrink = baselineLineHeight * 3
            let baselineUsageHeight = baseline.layoutManager.usageBoundsForTextContainer.height
            let collapsedUsageHeight = collapsed.layoutManager.usageBoundsForTextContainer.height
            XCTAssertEqual(baselineUsageHeight - collapsedUsageHeight, expectedShrink, accuracy: 0.5)
        }

        @MainActor
        func testMechanismA_DocumentStorageIsNeverMutated() {
            let collapsed = makeStack(collapsedLines: ["l2", "l3", "l4"])
            // Visual collapse must never touch the backing text storage.
            XCTAssertEqual(collapsed.contentStorage.textStorage?.string, documentText)
        }
    }
#endif
